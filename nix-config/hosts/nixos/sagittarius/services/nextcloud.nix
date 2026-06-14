{ config, pkgs, lib, ... }:

let
  nextcloudHost = "sagittarius.taildb4b48.ts.net";
  nextcloudPort = 8450; # Caddy front-end (Tailscale + LAN)
  nextcloudInternalPort = 8447; # internal nginx, localhost only
in
{
  # Redis: local cache + transactional file locking (matters for sync correctness).
  services.redis.servers.nextcloud = {
    enable = true;
    port = 6379;
    bind = "127.0.0.1";
  };

  services.nextcloud = {
    enable = true;
    package = pkgs.nextcloud33; # 33.x from nixos-26.05 (stable)
    hostName = nextcloudHost;
    https = true; # TLS terminated at Caddy

    # PostgreSQL over the local socket (peer auth); the module owns DB + role creation.
    database.createLocally = true;

    # Pure-Nix app management: no app store, shipped apps only.
    appstoreEnable = false;

    extraApps = {
      # OpenID Connect SSO — Google OAuth app.
      user_oidc = config.services.nextcloud.package.packages.apps.user_oidc;
    };

    # Redis-backed local cache + distributed locking.
    configureRedis = true;

    # Bulk data on the ZFS "lake" pool.
    datadir = "/data/lake/nextcloud";

    # Large desktop-sync uploads (also raises php memory/post/upload limits).
    maxUploadSize = "16G";

    config = {
      dbtype = "pgsql";
      adminuser = "admin";
      adminpassFile = config.age.secrets.nextcloud-admin-pass.path;
    };

    phpOptions = {
      "opcache.interned_strings_buffer" = "16";
      "opcache.memory_consumption" = "256";
      "max_execution_time" = "3600";
    };

    settings = {
      default_phone_region = "CH";
      maintenance_window_start = 2; # nightly jobs window (UTC)
      loglevel = 2; # warn
      filelocking.enabled = true;

      # Reverse-proxy: trust localhost (Caddy) and let per-request X-Forwarded-Proto/Host
      # decide the scheme/host. Do NOT set overwriteprotocol/overwritehost — hardcoding them
      # broke the LAN vhost previously. overwrite.cli.url fixes background/cron links.
      # Google OAuth/OIDC rejects the 'userinfo' key in the OIDC claims parameter.
      user_oidc.send_userinfo_claims = false;

      trusted_proxies = [ "127.0.0.1" "::1" ];
      "overwrite.cli.url" = "https://${nextcloudHost}:${toString nextcloudPort}";

      # hostName (bare) is auto-added by the module; add the :port and LAN variants.
      trusted_domains = [
        "${nextcloudHost}:${toString nextcloudPort}"
        "192.168.1.206"
        "192.168.1.206:${toString nextcloudPort}"
      ];
    };
  };

  users.users.nextcloud.extraGroups = [ "nas" ];

  # Pre-create the ZFS datadir with correct ownership before nextcloud-setup runs.
  systemd.tmpfiles.rules = [
    "d /data/lake/nextcloud 0750 nextcloud nextcloud - -"
  ];

  # Filesync-focused: disable non-essential shipped apps after install/upgrade.
  systemd.services.nextcloud-tune-apps = {
    description = "Disable non-essential Nextcloud apps (filesync-focused)";
    after = [ "nextcloud-setup.service" ];
    requires = [ "nextcloud-setup.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      for app in dashboard photos weather_status user_status recommendations firstrunwizard nextcloud_announcements; do
        ${config.services.nextcloud.occ}/bin/nextcloud-occ app:disable "$app" || true
      done
    '';
  };

  # Configure Google OpenID Connect SSO via the user_oidc app.
  # Prerequisites (one-time, in Google Cloud Console):
  #   - OAuth client must have this redirect URI authorised:
  #     https://sagittarius.taildb4b48.ts.net:8450/apps/user_oidc/code
  #   - Client ID + secret are in agenix secrets: google-oauth-client-id / google-oauth-client-secret
  systemd.services.nextcloud-oidc-config =
    let
      occ = "${config.services.nextcloud.occ}/bin/nextcloud-occ";
      clientIdFile = config.age.secrets.google-oauth-client-id.path;
      clientSecretFile = config.age.secrets.google-oauth-client-secret.path;
    in
    {
      description = "Configure Nextcloud OIDC provider (Google)";
      after = [ "nextcloud-tune-apps.service" ];
      requires = [ "nextcloud-setup.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "nextcloud";
        Group = "nextcloud";
        WorkingDirectory = "/data/lake/nextcloud";
      };
      script = ''
        set -euo pipefail
        OCC="${occ}"
        CLIENT_ID=$(cat ${clientIdFile})

        # user_oidc:provider is an upsert — creates on first run, updates on subsequent runs.
        # uid maps to Google's "sub" (stable numeric ID) — avoids the "claims" request parameter
        # that Google rejects when requesting email via the userinfo claims mechanism.
        # email and display name are mapped separately for human-readable profiles.
        "$OCC" user_oidc:provider "Google" \
          --clientid="$CLIENT_ID" \
          --clientsecret-file="${clientSecretFile}" \
          --discoveryuri="https://accounts.google.com/.well-known/openid-configuration" \
          --mapping-uid="sub" \
          --mapping-email="email" \
          --mapping-display-name="name" \
          --unique-uid=0

        "$OCC" app:enable user_oidc || true
        echo "nextcloud-oidc-config: Google OIDC provider configured."
      '';
    };

  # Internal nginx (module-managed), bound to localhost only; Caddy proxies to it.
  services.nginx = {
    enable = true;
    virtualHosts.${nextcloudHost}.listen = [
      { addr = "127.0.0.1"; port = nextcloudInternalPort; }
    ];
  };

  # --- Caddy front-ends (Caddy auto-sends X-Forwarded-Proto per scheme) ---
  # Tailscale (HTTPS + tailnet gate)
  services.caddy.virtualHosts."${nextcloudHost}:${toString nextcloudPort}" = {
    extraConfig = ''
      bind 100.119.78.108
      tls {
        get_certificate tailscale
      }
      tailscale_auth set_headers
      reverse_proxy 127.0.0.1:${toString nextcloudInternalPort} {
        header_up Host {http.request.host}
        header_up X-Real-IP {http.request.remote.host}
        header_up Tailscale-User-Login {http.request.header.Tailscale-User-Login}
        header_up Tailscale-User-Name {http.request.header.Tailscale-User-Name}
      }
      redir /.well-known/carddav /remote.php/dav 301
      redir /.well-known/caldav /remote.php/dav 301
      redir /.well-known/webfinger /index.php/.well-known/webfinger 301
      redir /.well-known/nodeinfo /index.php/.well-known/nodeinfo 301
    '';
  };

  # Local LAN (plain HTTP, no tailnet gate)
  services.caddy.virtualHosts."http://192.168.1.206:${toString nextcloudPort}" = {
    extraConfig = ''
      bind 192.168.1.206
      reverse_proxy 127.0.0.1:${toString nextcloudInternalPort} {
        header_up Host {http.request.host}
        header_up X-Real-IP {http.request.remote.host}
        header_up X-Forwarded-For {http.request.remote.host}
        header_up X-Forwarded-Proto {http.request.scheme}
        header_up X-Forwarded-Host {http.request.host}
      }
      redir /.well-known/carddav /remote.php/dav 301
      redir /.well-known/caldav /remote.php/dav 301
    '';
  };

  networking.firewall.allowedTCPPorts = [ nextcloudPort ];
}
