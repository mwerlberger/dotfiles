{ config, pkgs, ... }:

{
  # User configuration with nas group access
  users.users.prowlarr = {
    isSystemUser = true;
    group = "prowlarr";
    extraGroups = [ "nas" ];
  };

  users.users.sonarr = {
    isSystemUser = true;
    group = "sonarr";
    extraGroups = [ "nas" ];
  };

  users.users.radarr = {
    isSystemUser = true;
    group = "radarr";
    extraGroups = [ "nas" ];
  };

  users.users.lidarr = {
    isSystemUser = true;
    group = "lidarr";
    extraGroups = [ "nas" ];
  };

  users.users.readarr = {
    isSystemUser = true;
    group = "readarr";
    extraGroups = [ "nas" ];
  };

  users.groups = {
    prowlarr = {};
    sonarr = {};
    radarr = {};
    lidarr = {};
    readarr = {};
  };

  # Prowlarr
  services.prowlarr = {
    enable = true;
    openFirewall = false;
  };

  systemd.services.prowlarr = {
    after = [ "vpn-namespace.service" "wg-quick-mullvad.service" ];
    requires = [ "vpn-namespace.service" ];
    bindsTo = [ "wg-quick-mullvad.service" ];
    
    serviceConfig = {
      NetworkNamespacePath = "/run/netns/vpn";
    };
  };

  services.caddy.virtualHosts."sagittarius.taildb4b48.ts.net:9696" = {
    extraConfig = ''
      tls {
        get_certificate tailscale
      }
      tailscale_auth set_headers
      reverse_proxy 10.200.200.2:9696 {
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

  # Sonarr
  services.sonarr = {
    enable = true;
    openFirewall = false;
  };

  systemd.services.sonarr = {
    after = [ "vpn-namespace.service" "wg-quick-mullvad.service" ];
    requires = [ "vpn-namespace.service" ];
    bindsTo = [ "wg-quick-mullvad.service" ];
    
    serviceConfig = {
      NetworkNamespacePath = "/run/netns/vpn";
    };
  };

  services.caddy.virtualHosts."sagittarius.taildb4b48.ts.net:8989" = {
    extraConfig = ''
      tls {
        get_certificate tailscale
      }
      tailscale_auth set_headers
      reverse_proxy 10.200.200.2:8989 {
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

  # Radarr
  services.radarr = {
    enable = true;
    openFirewall = false;
  };

  systemd.services.radarr = {
    after = [ "vpn-namespace.service" "wg-quick-mullvad.service" ];
    requires = [ "vpn-namespace.service" ];
    bindsTo = [ "wg-quick-mullvad.service" ];
    
    serviceConfig = {
      NetworkNamespacePath = "/run/netns/vpn";
    };
  };

  services.caddy.virtualHosts."sagittarius.taildb4b48.ts.net:7878" = {
    extraConfig = ''
      tls {
        get_certificate tailscale
      }
      tailscale_auth set_headers
      reverse_proxy 10.200.200.2:7878 {
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

  # Lidarr
  services.lidarr = {
    enable = true;
    openFirewall = false;
  };

  systemd.services.lidarr = {
    after = [ "vpn-namespace.service" "wg-quick-mullvad.service" ];
    requires = [ "vpn-namespace.service" ];
    bindsTo = [ "wg-quick-mullvad.service" ];
    
    serviceConfig = {
      NetworkNamespacePath = "/run/netns/vpn";
    };
  };

  services.caddy.virtualHosts."sagittarius.taildb4b48.ts.net:8686" = {
    extraConfig = ''
      tls {
        get_certificate tailscale
      }
      tailscale_auth set_headers
      reverse_proxy 10.200.200.2:8686 {
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

  # Readarr
  services.readarr = {
    enable = true;
    openFirewall = false;
  };

  systemd.services.readarr = {
    after = [ "vpn-namespace.service" "wg-quick-mullvad.service" ];
    requires = [ "vpn-namespace.service" ];
    bindsTo = [ "wg-quick-mullvad.service" ];
    
    serviceConfig = {
      NetworkNamespacePath = "/run/netns/vpn";
    };
  };

  services.caddy.virtualHosts."sagittarius.taildb4b48.ts.net:8787" = {
    extraConfig = ''
      tls {
        get_certificate tailscale
      }
      tailscale_auth set_headers
      reverse_proxy 10.200.200.2:8787 {
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