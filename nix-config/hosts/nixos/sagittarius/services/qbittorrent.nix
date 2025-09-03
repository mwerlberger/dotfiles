{ config, pkgs, lib, ... }:

{
  services.qbittorrent = {
    enable = true;
    openFirewall = false;
  };

  # The qbittorrent service will create its own user automatically

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
      PrivateNetwork = lib.mkForce true;
    };
  };

  # Add qbittorrent user to nas group after service creates the user
  systemd.services.qbittorrent-fix-groups = {
    description = "Add qbittorrent user to nas group";
    after = [ "qbittorrent.service" ];
    wants = [ "qbittorrent.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = "
      if id qbittorrent >/dev/null 2>&1; then
        ${pkgs.shadow}/bin/usermod -a -G nas qbittorrent
      else
        echo 'qbittorrent user not found, skipping'
      fi
    ";
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