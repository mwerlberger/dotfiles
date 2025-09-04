{ config, pkgs, lib, ... }:

{
  services.prowlarr = {
    enable = true;
    openFirewall = false;
  };

  # Disable Prowlarr authentication since Tailscale provides security
  systemd.services.prowlarr-disable-auth = {
    description = "Disable Prowlarr authentication";
    after = [ "prowlarr.service" ];
    wants = [ "prowlarr.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      sleep 10
      # Disable authentication via API
      ${pkgs.curl}/bin/curl -X PUT "http://192.168.100.2:9696/api/v1/config/host" \
        -H "Content-Type: application/json" \
        -d '{"authenticationMethod": "None"}' || true
    '';
  };

  # The prowlarr service will create its own user automatically

  # Ensure data directory exists with proper permissions
  systemd.tmpfiles.rules = [
    "d /var/lib/prowlarr 0770 prowlarr nas -"
  ];

  # Override systemd service to run in VPN namespace
  systemd.services.prowlarr = {
    after = [ "wg-vpn.service" ];
    requires = [ "wg-vpn.service" ];
    serviceConfig = {
      NetworkNamespacePath = "/var/run/netns/vpn";
      PrivateNetwork = lib.mkForce true;
    };
  };

  # Add prowlarr user to nas group after service creates the user
  systemd.services.prowlarr-fix-groups = {
    description = "Add prowlarr user to nas group";
    after = [ "prowlarr.service" ];
    wants = [ "prowlarr.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = "
      if id prowlarr >/dev/null 2>&1; then
        ${pkgs.shadow}/bin/usermod -a -G nas prowlarr
      else
        echo 'prowlarr user not found, skipping'
      fi
    ";
  };

  # Reverse proxy configuration
  services.caddy.virtualHosts."sagittarius.taildb4b48.ts.net:9696" = {
    extraConfig = ''
      bind 100.119.78.108
      tls {
        get_certificate tailscale
      }
      tailscale_auth set_headers
      reverse_proxy 192.168.100.2:9696 {
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