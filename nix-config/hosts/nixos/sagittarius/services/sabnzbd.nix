{ config, pkgs, lib, ... }:

{
  # SABnzbd Usenet downloader
  services.sabnzbd = {
    enable = true;
    group = "nas";
  };

  # Override the default service to run in VPN namespace
  systemd.services.sabnzbd = {
    after = [ "vpn-namespace.service" "wg-quick-mullvad.service" ];
    requires = [ "vpn-namespace.service" ];
    bindsTo = [ "wg-quick-mullvad.service" ];

    # Configure host whitelist before service starts
    preStart = ''
      # Ensure config file exists
      if [ -f /var/lib/sabnzbd/sabnzbd.ini ]; then
        # Update host_whitelist if it exists
        if ${pkgs.gnugrep}/bin/grep -q "^host_whitelist" /var/lib/sabnzbd/sabnzbd.ini; then
          ${pkgs.gnused}/bin/sed -i 's/^host_whitelist = .*/host_whitelist = sagittarius, sagittarius.taildb4b48.ts.net, 10.200.200.2/' /var/lib/sabnzbd/sabnzbd.ini
        else
          # Add host_whitelist to [misc] section if it doesn't exist
          ${pkgs.gnused}/bin/sed -i '/^\[misc\]/a host_whitelist = sagittarius, sagittarius.taildb4b48.ts.net, 10.200.200.2' /var/lib/sabnzbd/sabnzbd.ini
        fi
      fi
    '';

    serviceConfig = {
      NetworkNamespacePath = "/run/netns/vpn";
      ExecStart = lib.mkForce "${pkgs.sabnzbd}/bin/sabnzbd -s 0.0.0.0:8085 -d -f /var/lib/sabnzbd/sabnzbd.ini";
    };
  };

  # Ensure data directories exist with proper permissions
  systemd.tmpfiles.rules = [
    "d /var/lib/sabnzbd 0770 sabnzbd nas -"
    "d /data/lake/media/usenet 0770 sabnzbd nas -"
    "d /data/lake/media/usenet/complete 0770 sabnzbd nas -"
    "d /data/lake/media/usenet/incomplete 0770 sabnzbd nas -"
  ];

  # Reverse proxy configuration (accessible via Tailscale)
  # Proxies to SABnzbd running in VPN namespace
  # Note: Caddy handles HTTPS (via Tailscale cert), backend connection is HTTP
  services.caddy.virtualHosts."sagittarius.taildb4b48.ts.net:8090" = {
    extraConfig = ''
      tls {
        get_certificate tailscale
      }
      tailscale_auth set_headers
      reverse_proxy http://10.200.200.2:8085 {
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
