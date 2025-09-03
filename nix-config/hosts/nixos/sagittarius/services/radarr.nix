{ config, pkgs, lib, ... }:

{
  services.radarr = {
    enable = true;
    openFirewall = false;
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
      bind 100.119.78.108
      tls {
        get_certificate tailscale
      }
      tailscale_auth
      reverse_proxy 192.168.100.2:7878 {
        header_up Host {http.request.host}
        header_up X-Real-IP {http.request.remote.host}
        header_up X-Forwarded-For {http.request.remote.host}
        header_up X-Forwarded-Proto {http.request.scheme}
      }
    '';
  };
}