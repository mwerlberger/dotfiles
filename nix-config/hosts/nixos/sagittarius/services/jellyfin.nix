{ config, pkgs, lib, ... }:

let
  # Jellyfin host configuration for reverse proxy
  jellyfinHost = "sagittarius.taildb4b48.ts.net";
in
{
  services.jellyfin = {
    enable = true;
    openFirewall = false; # We'll use reverse proxy instead
    dataDir = "/data/lake/media/jellyfin";
  };

  # Add jellyfin user to nas group for media directory access
  users.users.${config.services.jellyfin.user}.extraGroups = [ "nas" ];

  # Ensure media directory exists and has proper permissions
  systemd.tmpfiles.rules = [
    "d /data/lake/media/jellyfin 0770 jellyfin nas -"
    "d /var/lib/jellyfin-secrets 0750 ${config.services.jellyfin.user} ${config.services.jellyfin.group} -"
  ];

  # Create OAuth secrets service for Jellyfin
  systemd.services.jellyfin-oauth-secrets = {
    description = "Generate Jellyfin OAuth secrets";
    wantedBy = [ "jellyfin.service" ];
    before = [ "jellyfin.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      cat > /var/lib/jellyfin-secrets/oauth.env << EOF
GOOGLE_CLIENT_ID=$(cat ${config.age.secrets.google-oauth-client-id.path})
GOOGLE_CLIENT_SECRET=$(cat ${config.age.secrets.google-oauth-client-secret.path})
EOF
      chown ${config.services.jellyfin.user}:${config.services.jellyfin.group} /var/lib/jellyfin-secrets/oauth.env
      chmod 600 /var/lib/jellyfin-secrets/oauth.env
    '';
  };

  # Configure Jellyfin service to use OAuth secrets
  systemd.services.jellyfin.serviceConfig.EnvironmentFile = "/var/lib/jellyfin-secrets/oauth.env";

  # Manual SSO plugin setup - requires manual configuration via web UI
  # The plugin needs to be installed manually through Jellyfin's web interface:
  # 1. Go to Dashboard > Plugins > Catalog
  # 2. Add repository: https://raw.githubusercontent.com/9p4/jellyfin-plugin-sso/manifest-release/manifest.json
  # 3. Install SSO Authentication plugin
  # 4. Configure Google OIDC in plugin settings with environment variables

  # Add reverse proxy configuration to Caddy
  services.caddy.virtualHosts."${jellyfinHost}:8445" = {
    extraConfig = ''
      bind 100.119.78.108
      tls {
        get_certificate tailscale
      }
      tailscale_auth
      reverse_proxy 127.0.0.1:8096 {
        header_up Host {http.request.host}
        header_up X-Real-IP {http.request.remote.host}
        header_up X-Forwarded-For {http.request.remote.host}
        header_up X-Forwarded-Proto {http.request.scheme}
      }
    '';
  };
  services.caddy.virtualHosts."192.168.1.206:8445" = {
    extraConfig = ''
      bind 192.168.1.206 
      tls internal
      reverse_proxy 127.0.0.1:8096 {
        header_up Host {http.request.host}
        header_up X-Real-IP {http.request.remote.host}
        header_up X-Forwarded-For {http.request.remote.host}
        header_up X-Forwarded-Proto {http.request.scheme}
      }
    '';
  };
  networking.firewall.allowedTCPPorts = [
    8445
  ];
}