{ config
, pkgs
, lib
, ...
}:

# Public (internet-facing) edge for a hand-picked group of outside people.
#
# Shape: cloudflared makes an *outbound* connection to Cloudflare, so nothing new is
# listening on the LAN or on the host's public IPv6 -- `networking.firewall` is
# deliberately untouched by this file. Cloudflare Access authenticates the visitor by
# email one-time-PIN against a reusable Access policy, then the tunnel hands the request to
# a loopback-only Caddy vhost which independently verifies Cloudflare's signed JWT
# before anything reaches the application.
#
# Four gates, any one of which alone stops an unauthorised request:
#   1. the Cloudflare Access policy (allow-list of email addresses)
#   2. `jwtauth` here, against the team JWKS + this app's audience tag
#   3. the per-service path deny-list
#   4. the application's own share-token auth (Immich share key / Nextcloud link token)
#
# See services/PUBLIC-SHARING.md for the runbook.

let
  # Master switch. Leave `false` until the Cloudflare side exists and
  # secrets/cloudflared-credentials.age has been created -- agenix fails the rebuild if
  # the .age file is missing, and cloudflared crash-loops on a placeholder tunnel id.
  enable = true;

  # https://<cfTeam>.cloudflareaccess.com -- Zero Trust -> Settings -> Custom Pages, or
  # the team name in the dashboard URL.
  cfTeam = "rapid-rain-991e";

  # UUID printed by `cloudflared tunnel create sagittarius-public`.
  tunnelId = "18eb90a3-3238-4970-ab9c-44232943f698";

  # One entry per publicly published service.
  #
  # `localPort` is a loopback-only Caddy listener that only cloudflared talks to; keep it
  # out of the ranges already in use (8441-8452, 8461 -- see the host README port table).
  # `audTag` is the Application Audience tag from the Access application; it is what stops
  # a token minted for one app being replayed against another.
  published = {
    photos = {
      hostname = "photos.werlberger.org";
      localPort = 8460;
      upstream = "127.0.0.1:2283"; # Immich
      audTag = "82caac2b83c2f2b276a1fa1de775426e2de7fcb51786eff97c4df2dc2b2c0ffa";
      # Immich's admin and login surfaces never need to be reachable from the internet:
      # family arrives on a /share/<key> link, which authenticates with the share key.
      # Defence in depth -- Immich returns 401 on these unauthenticated anyway. Re-check
      # after an Immich upgrade.
      denyPaths = [
        "/admin*"
        "/auth/*"
        "/api/admin/*"
        "/api/auth/*"
        "/api/oauth/*"
        "/api/jobs/*"
        "/api/system-config/*"
        "/api/system-metadata/*"
        "/api/api-keys/*"
        "/api/sessions/*"
        "/api/users*"
      ];
    };

    # Escape hatch for files over Cloudflare's 100 MB request-body cap. Immich's web
    # uploader sends a single-shot POST (browsers may not set Transfer-Encoding, so the
    # mobile app's chunking trick is unavailable to it), whereas Nextcloud's web uploader
    # chunks by default at ~10 MiB via DAV and is unaffected. Retire this once upstream
    # Immich ships chunked web uploads.
    drop = {
      hostname = "drop.werlberger.org";
      localPort = 8462;
      upstream = "127.0.0.1:8447"; # Nextcloud's internal nginx
      audTag = "2ca766918e64679a106f4e9a7c6aac79560e37236ccae95a50bfc5672deb926e";
      denyPaths = [
        "/login"
        "/index.php/login"
        "/settings/*"
        "/index.php/settings/*"
        "/apps/user_oidc/*"
        "/index.php/apps/user_oidc/*"
        "/ocs/*"
        "/index.php/ocs/*"
        "/remote.php/webdav*"
      ];
    };
  };

  # Loopback-only vhost fronting one published service.
  mkVhost = _name: s: lib.nameValuePair "http://${s.hostname}:${toString s.localPort}" {
    extraConfig = ''
      bind 127.0.0.1

      route {
        # Only cloudflared, on this host, may reach this listener. Belt-and-braces next
        # to `bind 127.0.0.1`.
        @notLocal not remote_ip 127.0.0.1
        abort @notLocal

        # Drop anything a client could have forged before we establish identity ourselves.
        request_header -Cf-Access-Authenticated-User-Email
        request_header -X-Remote-User
        request_header -X-Remote-Email

        @blocked path ${lib.concatStringsSep " " s.denyPaths}
        respond @blocked 404

        # Verify Cloudflare's signature. Access is the first gate, not the only one: a
        # request that somehow reaches this port without a valid, correctly-audienced
        # token is rejected here, before the application sees it.
        jwtauth {
          jwk_url https://${cfTeam}.cloudflareaccess.com/cdn-cgi/access/certs
          sign_alg RS256
          from_header Cf-Access-Jwt-Assertion
          from_cookies CF_Authorization
          issuer_whitelist https://${cfTeam}.cloudflareaccess.com
          audience_whitelist ${s.audTag}
          user_claims email
        }

        reverse_proxy ${s.upstream} {
          header_up Host {http.request.host}
          header_up X-Real-IP {http.request.header.Cf-Connecting-Ip}
          header_up X-Forwarded-For {http.request.header.Cf-Connecting-Ip}
          header_up X-Forwarded-Proto https
        }
      }
    '';
  };
in
{
  config = lib.mkIf enable {
    # Tunnel credentials JSON from `cloudflared tunnel create`. Read by PID1 via
    # LoadCredential (see the cloudflared module), so the DynamicUser never sees the file.
    age.secrets.cloudflared-credentials = {
      file = ../../../../secrets/cloudflared-credentials.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };

    services.cloudflared = {
      enable = true;
      tunnels.${tunnelId} = {
        credentialsFile = config.age.secrets.cloudflared-credentials.path;
        # Anything not explicitly published is not reachable, even if DNS points here.
        default = "http_status:404";
        # NB: the cloudflared module uses the *attribute name* as the ingress
        # hostname, so this must be keyed by the FQDN rather than by the short
        # service name -- otherwise every request falls through to the 404 default.
        ingress = lib.mapAttrs'
          (_: s: lib.nameValuePair s.hostname {
            service = "http://127.0.0.1:${toString s.localPort}";
          })
          published;
      };
      # Deliberately no `certificateFile`: cert.pem is an account-wide credential and is
      # only needed for managing DNS/routes from the host. Those are created in the
      # dashboard, so it never lands on the NAS.
    };

    # Blast-radius containment. cloudflared is the one process here that talks to the
    # public internet, so assume it can be compromised and make that as boring as
    # possible: it may reach the Cloudflare edge, DNS and loopback, and nothing else.
    # In particular it cannot reach the LAN, the tailnet, or the 10.200.200.0/24 veth to
    # the Mullvad namespace.
    #
    # systemd checks IPAddressAllow FIRST and a match there grants access outright --
    # there is no longest-prefix-match between the two lists (systemd.resource-control(5)).
    # So this has to be deny-by-default plus explicit allows; "allow any, deny the private
    # ranges" silently permits everything.
    #
    # The edge ranges are region{1,2}.v2.argotunnel.com (QUIC/UDP 7844). If Cloudflare ever
    # adds a range, the tunnel fails to connect -- re-check with:
    #   dig +short region1.v2.argotunnel.com region2.v2.argotunnel.com
    #
    # NOTE: this silently does nothing if systemd lacks +BPF_FRAMEWORK. Verify enforcement
    # empirically, not by reading the unit -- see PUBLIC-SHARING.md.
    systemd.services."cloudflared-tunnel-${tunnelId}" = {
      # The startup connectivity precheck dials api.cloudflare.com, which the allow-list
      # below deliberately blocks -- a locally-managed tunnel with a credentials file never
      # needs the API at runtime. Skip the check rather than widen the allow-list, so that a
      # real failure later is not lost among an expected one.
      environment.TUNNEL_NO_PRECHECKS = "true";

      serviceConfig = {
        IPAddressDeny = "any";
        IPAddressAllow = [
          "localhost" # origin vhosts on 127.0.0.1 + cloudflared's own metrics listener
          "198.41.192.0/24" # region1.v2.argotunnel.com
          "198.41.200.0/24" # region2.v2.argotunnel.com
          "2606:4700:a0::/48"
          "2606:4700:a8::/48"
          "100.100.100.100" # MagicDNS, the active resolver in /etc/resolv.conf
          "fd7a:115c:a1e0::53"
          "1.1.1.1" # fallbacks from networking.nameservers
          "8.8.8.8"
        ];

        CapabilityBoundingSet = [ "" ];
        AmbientCapabilities = [ "" ];
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        ProtectSystem = "strict";
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [ "@system-service" "~@privileged" "~@resources" ];
      };
    };

    services.caddy.virtualHosts = lib.mapAttrs' mkVhost published;

    # Nextcloud answers on its own hostname today; teach it about the drop vhost. The
    # internal nginx is currently the only vhost on 127.0.0.1:8447 so it would probably
    # match as the default server, but relying on that is fragile.
    services.nextcloud.settings.trusted_domains = [ published.drop.hostname ];
    services.nginx.virtualHosts.${config.services.nextcloud.hostName}.serverAliases = [
      published.drop.hostname
    ];
  };
}
