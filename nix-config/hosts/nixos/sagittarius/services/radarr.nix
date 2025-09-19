{ config, pkgs, lib, ... }:

{
  services.radarr = {
    enable = true;
    openFirewall = false;
  };

  # Configure Radarr to use a different port to avoid conflict with Caddy
  systemd.services.radarr.environment.RADARR__SERVER__PORT = lib.mkForce "7879";

  # Disable Radarr authentication since Tailscale provides security
  systemd.services.radarr-disable-auth = {
    description = "Disable Radarr authentication";
    after = [ "radarr.service" ];
    wants = [ "radarr.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      sleep 10
      # Disable authentication via API
      ${pkgs.curl}/bin/curl -X PUT "http://localhost:7879/api/v3/config/host" \
        -H "Content-Type: application/json" \
        -d '{"authenticationMethod": "None"}' || true
    '';
  };

  # The radarr service will create its own user automatically

  # Ensure data directory exists with proper permissions
  systemd.tmpfiles.rules = [
    "d /data/lake/media/radarr 0770 radarr nas -"
    "d /data/lake/media/movies 0770 radarr nas -"
  ];

  # Override systemd service to run in VPN namespace
  systemd.services.radarr = {
    after = [ "wg-vpn.service" ];
    requires = [ "wg-vpn.service" ];
    serviceConfig = {
      NetworkNamespacePath = "/var/run/netns/vpn";
      PrivateNetwork = lib.mkForce true;
    };
  };

  # Add radarr user to nas group after service creates the user
  systemd.services.radarr-fix-groups = {
    description = "Add radarr user to nas group";
    after = [ "radarr.service" ];
    wants = [ "radarr.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = "
      if id radarr >/dev/null 2>&1; then
        ${pkgs.shadow}/bin/usermod -a -G nas radarr
      else
        echo 'radarr user not found, skipping'
      fi
    ";
  };

  # Reverse proxy configuration
  services.caddy.virtualHosts."sagittarius.taildb4b48.ts.net:7878" = {
    extraConfig = ''
      tls {
        get_certificate tailscale
      }
      tailscale_auth set_headers
      reverse_proxy localhost:7879 {
        header_up Host {http.request.host}
        header_up X-Real-IP {http.request.remote.host}
        header_up X-Forwarded-For {http.request.remote.host}
        header_up X-Forwarded-Proto {http.request.scheme}
        header_up X-Webauth-User {http.request.header.Tailscale-User-Login}
        header_up X-Webauth-Name {http.request.header.Tailscale-User-Name}
        header_up X-Webauth-Email {http.request.header.Tailscale-User-Login}
        header_up Remote-User {http.request.header.Tailscale-User-Login}
      }
    '';
  };
}