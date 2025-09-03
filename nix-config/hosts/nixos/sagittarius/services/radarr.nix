{ config, pkgs, lib, ... }:

{
  services.radarr = {
    enable = true;
    openFirewall = false;
    user = "radarr";
    group = "nas";
  };

  # Create radarr user and ensure it's in nas group
  users.users.radarr = {
    isSystemUser = true;
    group = "nas";
    extraGroups = [ "nas" ];
  };

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
      PrivateNetwork = true;
    };
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