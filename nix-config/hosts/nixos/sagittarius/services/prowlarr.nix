{ config, pkgs, lib, ... }:

{
  services.prowlarr = {
    enable = true;
    openFirewall = false;
  };

  # Ensure prowlarr user is in nas group
  users.users.${config.services.prowlarr.user}.extraGroups = [ "nas" ];

  # Ensure data directory exists with proper permissions
  systemd.tmpfiles.rules = [
    "d /var/lib/prowlarr 0770 ${config.services.prowlarr.user} nas -"
  ];

  # Override systemd service to run in VPN namespace
  systemd.services.prowlarr = {
    after = [ "wg-vpn.service" ];
    requires = [ "wg-vpn.service" ];
    serviceConfig = {
      NetworkNamespacePath = "/var/run/netns/vpn";
      PrivateNetwork = true;
    };
  };

  # Reverse proxy configuration
  services.caddy.virtualHosts."sagittarius.taildb4b48.ts.net:9696" = {
    extraConfig = ''
      bind 100.119.78.108
      tls {
        get_certificate tailscale
      }
      tailscale_auth
      reverse_proxy 192.168.100.2:9696 {
        header_up Host {http.request.host}
        header_up X-Real-IP {http.request.remote.host}
        header_up X-Forwarded-For {http.request.remote.host}
        header_up X-Forwarded-Proto {http.request.scheme}
      }
    '';
  };
}