{ config, pkgs, lib, ... }:

{
  services.sonarr = {
    enable = true;
    openFirewall = false;
    user = "sonarr";
    group = "nas";
  };

  # Create sonarr user and ensure it's in nas group
  users.users.sonarr = {
    isSystemUser = true;
    group = "nas";
    extraGroups = [ "nas" ];
  };

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
      PrivateNetwork = true;
    };
  };

  # Reverse proxy configuration
  services.caddy.virtualHosts."sagittarius.taildb4b48.ts.net:8989" = {
    extraConfig = ''
      bind 100.119.78.108
      tls {
        get_certificate tailscale
      }
      tailscale_auth
      reverse_proxy 192.168.100.2:8989 {
        header_up Host {http.request.host}
        header_up X-Real-IP {http.request.remote.host}
        header_up X-Forwarded-For {http.request.remote.host}
        header_up X-Forwarded-Proto {http.request.scheme}
      }
    '';
  };
}