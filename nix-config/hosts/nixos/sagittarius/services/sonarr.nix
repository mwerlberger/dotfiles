{ config, pkgs, lib, ... }:

{
  services.sonarr = {
    enable = true;
    openFirewall = false;
  };

  # Disable Sonarr authentication since Tailscale provides security
  systemd.services.sonarr-disable-auth = {
    description = "Disable Sonarr authentication";
    after = [ "sonarr.service" ];
    wants = [ "sonarr.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      sleep 10
      # Disable authentication via API
      ${pkgs.curl}/bin/curl -X PUT "http://192.168.100.2:8989/api/v3/config/host" \
        -H "Content-Type: application/json" \
        -d '{"authenticationMethod": "None"}' || true
    '';
  };

  # The sonarr service will create its own user automatically

  # Ensure data directory exists with proper permissions
  systemd.tmpfiles.rules = [
    "d /data/lake/media/sonarr 0770 sonarr nas -"
    "d /data/lake/media/tv 0770 sonarr nas -"
  ];

  # Override systemd service to run in VPN namespace
  systemd.services.sonarr = {
    after = [ "wg-vpn.service" ];
    requires = [ "wg-vpn.service" ];
    serviceConfig = {
      NetworkNamespacePath = "/var/run/netns/vpn";
      PrivateNetwork = lib.mkForce true;
    };
  };

  # Add sonarr user to nas group after service creates the user
  systemd.services.sonarr-fix-groups = {
    description = "Add sonarr user to nas group";
    after = [ "sonarr.service" ];
    wants = [ "sonarr.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = "
      if id sonarr >/dev/null 2>&1; then
        ${pkgs.shadow}/bin/usermod -a -G nas sonarr
      else
        echo 'sonarr user not found, skipping'
      fi
    ";
  };

  # Reverse proxy configuration
  services.caddy.virtualHosts."sagittarius.taildb4b48.ts.net:8989" = {
    extraConfig = ''
      tls {
        get_certificate tailscale
      }
      tailscale_auth set_headers
      reverse_proxy 192.168.100.2:8989 {
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