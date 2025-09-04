{ config, pkgs, lib, ... }:

{
  # Create a shared group for all media services in case it doesn't exist yet
  users.groups.media = {};



  # Ensure media directories exist with proper permissions
  systemd.tmpfiles.rules = [
    "d /data/lake/media/movies 0770 root nas -"
    "d /data/lake/media/tv 0770 root nas -"
    "d /data/lake/media/downloads 0770 root nas -"
    "d /data/lake/media/torrents 0770 root nas -"
    "d /data/lake/media/torrents/.incomplete 0770 transmission cross-seed -"
    "d /data/lake/media/torrents/.watch 0770 transmission cross-seed -"
    # Create nixarr state directory with root ownership and open permissions for testing
    "d /data/lake/media/.nixarr-state 0777 root root -"
  ];
  
  # Add nixarr service users to the media group for shared access
  users.users = {
    sonarr.extraGroups = [ "media" ];
    radarr.extraGroups = [ "media" ];
    prowlarr.extraGroups = [ "media" ];
    transmission.extraGroups = [ "media" ];
  };

  # Configure nixarr with VPN support
  nixarr = {
    enable = true;
    
    # VPN configuration using your existing Mullvad config
    vpn = {
      enable = true;
      wgConf = config.age.secrets.mullvad-zrh.path;
    };

    # Enable media server applications
    prowlarr = {
      enable = true;
    };

    radarr = {
      enable = true;
    };

    sonarr = {
      enable = true;
    };

    audiobookshelf = {
      enable = true;
      openFirewall = false; # We'll use reverse proxy instead
      # Optional: specify a custom port if needed
    };

    transmission = {
      enable = true;
      # Use transmission instead of qbittorrent as it's better supported by nixarr
      # You can migrate your torrents from qbittorrent later if needed
      openFirewall = false;
    };

    # Media directories - nixarr will handle permissions automatically
    mediaDir = "/data/lake/media";
    # Use default stateDir location instead of custom path
  };

  # Configure systemd services for proper ordering and reliability
  systemd.services = {
    # Fix VPN service to prevent interference with Caddy/Tailscale
    wg = {
      # Ensure VPN starts after network is fully ready and doesn't block Caddy
      after = [ "network-online.target" "tailscaled.service" ];
      wants = [ "network-online.target" ];
      before = [ ]; # Remove any dependencies that might block Caddy
      # Add timeout to prevent indefinite hanging
      serviceConfig = {
        TimeoutStartSec = "60s";
        TimeoutStopSec = "30s";
        Restart = "on-failure";
        RestartSec = "10s";
        StartLimitBurst = 3;
        StartLimitIntervalSec = 300;
      };
    };

    # Ensure Caddy starts independently of VPN
    caddy = {
      after = [ "tailscaled.service" ];
      # Remove any dependency on VPN service
      conflicts = [ ];
    };

    # Disable authentication for all arr services since Tailscale provides security
    prowlarr-disable-auth = {
      description = "Disable Prowlarr authentication";
      after = [ "prowlarr.service" ];
      wants = [ "prowlarr.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        sleep 15
        # Wait for service to be fully ready before configuring
        ${pkgs.curl}/bin/curl -X PUT "http://localhost:9696/api/v1/config/host" \
          -H "Content-Type: application/json" \
          -d '{"authenticationMethod": "None"}' || true
      '';
    };

    radarr-disable-auth = {
      description = "Disable Radarr authentication";
      after = [ "radarr.service" ];
      wants = [ "radarr.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        sleep 15
        ${pkgs.curl}/bin/curl -X PUT "http://localhost:7878/api/v3/config/host" \
          -H "Content-Type: application/json" \
          -d '{"authenticationMethod": "None"}' || true
      '';
    };

    sonarr-disable-auth = {
      description = "Disable Sonarr authentication";
      after = [ "sonarr.service" ];
      wants = [ "sonarr.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        sleep 15
        ${pkgs.curl}/bin/curl -X PUT "http://localhost:8989/api/v3/config/host" \
          -H "Content-Type: application/json" \
          -d '{"authenticationMethod": "None"}' || true
      '';
    };
  };


  # Setting up the reverse proxy for nixarr services in Caddy
  # Transmission on :4999
  services.caddy.virtualHosts."sagittarius.taildb4b48.ts.net:8499" = {
    extraConfig = ''
      bind 100.119.78.108
      tls {
        get_certificate tailscale
      }
      tailscale_auth set_headers
      reverse_proxy 127.0.0.1:9091 {
        header_up Host {http.request.host}
        header_up X-Real-IP {http.request.remote.host}
        header_up X-Webauth-User {http.request.header.Tailscale-User-Login}
        header_up X-Webauth-Name {http.request.header.Tailscale-User-Name}
        header_up X-Webauth-Email {http.request.header.Tailscale-User-Login}
        header_up Remote-User {http.request.header.Tailscale-User-Login}
      }
    '';
  };

  # Sonarr on :8500
  services.caddy.virtualHosts."sagittarius.taildb4b48.ts.net:8500" = {
    extraConfig = ''
      bind 100.119.78.108
      tls {
        get_certificate tailscale
      }
      tailscale_auth set_headers
      reverse_proxy 127.0.0.1:8989 {
        header_up Host {http.request.host}
        header_up X-Real-IP {http.request.remote.host}
        header_up X-Forwarded-For {http.request.remote.host}
        header_up X-Forwarded-Proto {http.request.scheme}
        header_up X-Webauth-User {http.request.header.Tailscale-User-Login}
        header_up X-Webauth-Name {http.request.header.Tailscale-User-Name}
        header_up X-Webauth-Email {http.request.header.Tailscale-User-Login}
      }
    '';
  };
  # Radarr on :8501
  services.caddy.virtualHosts."sagittarius.taildb4b48.ts.net:8501" = {
    extraConfig = ''
      bind 100.119.78.108
      tls {
        get_certificate tailscale
      }
      tailscale_auth set_headers
      reverse_proxy 127.0.0.1:7878 {
        header_up Host {http.request.host}
        header_up X-Real-IP {http.request.remote.host}
        header_up X-Forwarded-For {http.request.remote.host}
        header_up X-Forwarded-Proto {http.request.scheme}
        header_up X-Webauth-User {http.request.header.Tailscale-User-Login}
        header_up X-Webauth-Name {http.request.header.Tailscale-User-Name}
        header_up X-Webauth-Email {http.request.header.Tailscale-User-Login}
      }
    '';
  };
  # Prowlarr on :8502
  services.caddy.virtualHosts."sagittarius.taildb4b48.ts.net:8502" = {
    extraConfig = ''
      bind 100.119.78.108
      tls {
        get_certificate tailscale
      }
      tailscale_auth set_headers
      reverse_proxy 127.0.0.1:9696 {
        header_up Host {http.request.host}
        header_up X-Real-IP {http.request.remote.host}
        header_up X-Forwarded-For {http.request.remote.host}
        header_up X-Forwarded-Proto {http.request.scheme}
        header_up X-Webauth-User {http.request.header.Tailscale-User-Login}
        header_up X-Webauth-Name {http.request.header.Tailscale-User-Name}
        header_up X-Webauth-Email {http.request.header.Tailscale-User-Login}
      }
    '';
  };
  # Audiobookshelf on :8503
  services.caddy.virtualHosts."sagittarius.taildb4b48.ts.net:8503" = {
    extraConfig = ''
      bind 100.119.78.108
      tls {
        get_certificate tailscale
      }
      tailscale_auth set_headers
      reverse_proxy 127.0.0.1:9292 {
        header_up Host {http.request.host}
        header_up X-Real-IP {http.request.remote.host}
        header_up X-Forwarded-For {http.request.remote.host}
        header_up X-Forwarded-Proto {http.request.scheme}
        header_up X-Webauth-User {http.request.header.Tailscale-User-Login}
        header_up X-Webauth-Name {http.request.header.Tailscale-User-Name}
        header_up X-Webauth-Email {http.request.header.Tailscale-User-Login}
      }
    '';
  };
}