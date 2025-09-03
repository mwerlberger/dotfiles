{ config, pkgs, lib, ... }:

{
  services.qbittorrent = {
    enable = true;
    openFirewall = false;
    user = "qbittorrent";
    group = "nas";
    port = 8080;
  };

  # Create qbittorrent user and ensure it's in nas group
  users.users.qbittorrent = {
    isSystemUser = true;
    group = "nas";
    extraGroups = [ "nas" ];
  };

  # Ensure data directories exist with proper permissions
  systemd.tmpfiles.rules = [
    "d /data/lake/media/qbittorrent 0770 qbittorrent nas -"
    "d /data/lake/media/downloads 0770 qbittorrent nas -"
    "d /data/lake/media/downloads/complete 0770 qbittorrent nas -"
    "d /data/lake/media/downloads/incomplete 0770 qbittorrent nas -"
  ];

  # Override systemd service to run in VPN namespace
  systemd.services.qbittorrent = {
    after = [ "wg-vpn.service" ];
    requires = [ "wg-vpn.service" ];
    serviceConfig = {
      NetworkNamespacePath = "/var/run/netns/vpn";
      PrivateNetwork = true;
    };
  };

  # Reverse proxy configuration
  services.caddy.virtualHosts."sagittarius.taildb4b48.ts.net:8080" = {
    extraConfig = ''
      bind 100.119.78.108
      tls {
        get_certificate tailscale
      }
      tailscale_auth
      reverse_proxy 192.168.100.2:8080 {
        header_up Host {http.request.host}
        header_up X-Real-IP {http.request.remote.host}
        header_up X-Forwarded-For {http.request.remote.host}
        header_up X-Forwarded-Proto {http.request.scheme}
      }
    '';
  };
}