{ config, pkgs, lib, ... }:

{
  # Simple qBittorrent configuration without VPN
  services.qbittorrent = {
    enable = true;
    openFirewall = false;
  };

  # Override the default service to use port 8081 and run in VPN namespace
  systemd.services.qbittorrent = {
    after = [ "vpn-namespace.service" "wg-quick-mullvad.service" ];
    requires = [ "vpn-namespace.service" ];
    bindsTo = [ "wg-quick-mullvad.service" ];

    serviceConfig = {
      NetworkNamespacePath = "/run/netns/vpn";
      ExecStart = lib.mkForce "${pkgs.qbittorrent-nox}/bin/qbittorrent-nox --profile=/var/lib/qBittorrent --webui-port=8081 --confirm-legal-notice";
    };
  };

  # Ensure data directories exist with proper permissions
  systemd.tmpfiles.rules = [
    "d /var/lib/qBittorrent 0770 qbittorrent qbittorrent -"
    "d /data/lake/media/qbittorrent 0770 qbittorrent nas -"
    "d /data/lake/media/downloads 0770 qbittorrent nas -"
    "d /data/lake/media/downloads/complete 0770 qbittorrent nas -"
    "d /data/lake/media/downloads/incomplete 0770 qbittorrent nas -"
  ];

  # Add qbittorrent user to nas group after service creates the user
  systemd.services.qbittorrent-fix-groups = {
    description = "Add qbittorrent user to nas group";
    after = [ "qbittorrent.service" ];
    wants = [ "qbittorrent.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      if id qbittorrent >/dev/null 2>&1; then
        ${pkgs.shadow}/bin/usermod -a -G nas qbittorrent
      else
        echo 'qbittorrent user not found, skipping'
      fi
    '';
  };

  # Reverse proxy configuration (accessible via Tailscale)
  # Proxies to qBittorrent running in VPN namespace
  services.caddy.virtualHosts."sagittarius.taildb4b48.ts.net:8080" = {
    extraConfig = ''
      tls {
        get_certificate tailscale
      }
      tailscale_auth set_headers
      reverse_proxy 10.200.200.2:8081 {
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
