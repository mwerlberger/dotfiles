{ config, pkgs, lib, ... }:

let
  # Homarr host configuration for reverse proxy
  homarrHost = "sagittarius.taildb4b48.ts.net";
  homarrPort = 8447;
  # Internal Homarr port
  homarrInternalPort = 7575;
in
{
  # Enable Docker
  virtualisation.docker.enable = true;

  # Add necessary users to docker group
  users.users.mw.extraGroups = [ "docker" ];

  # Create directories with proper permissions
  systemd.tmpfiles.rules = [
    "d /data/lake/.state/homarr 0770 mw nas - -"
    "d /data/lake/.state/homarr/configs 0770 mw nas - -"
    "d /data/lake/.state/homarr/icons 0770 mw nas - -"
    "d /data/lake/.state/homarr/data 0770 mw nas - -"
  ];

  # Homarr Docker container via systemd
  systemd.services.homarr = {
    description = "Homarr - Customizable browser's home page";
    wantedBy = [ "multi-user.target" ];
    after = [ "docker.service" "network-online.target" "zfs-mount.service" ];
    requires = [ "docker.service" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = [
        # Pull the latest image
        "${pkgs.docker}/bin/docker pull ghcr.io/ajnart/homarr:latest"
        # Remove old container if it exists
        "-${pkgs.docker}/bin/docker rm -f homarr"
      ];
      ExecStart = ''
        ${pkgs.docker}/bin/docker run -d \
          --name homarr \
          --restart unless-stopped \
          -p 127.0.0.1:${toString homarrInternalPort}:7575 \
          -v /data/lake/.state/homarr/configs:/app/data/configs \
          -v /data/lake/.state/homarr/icons:/app/public/icons \
          -v /data/lake/.state/homarr/data:/data \
          -e BASE_URL=https://${homarrHost}:${toString homarrPort} \
          -e DISABLE_ANALYTICS=true \
          ghcr.io/ajnart/homarr:latest
      '';
      ExecStop = "${pkgs.docker}/bin/docker stop homarr";

      # Restart on failure
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };

  # Add reverse proxy configuration to Caddy
  services.caddy.virtualHosts."${homarrHost}:${toString homarrPort}" = {
    extraConfig = ''
      bind 100.119.78.108
      tls {
        get_certificate tailscale
      }

      # Tailscale authentication - this protects the entire service
      tailscale_auth set_headers

      # Homarr reverse proxy
      reverse_proxy 127.0.0.1:${toString homarrInternalPort} {
        header_up Host {http.request.host}
        header_up X-Real-IP {http.request.remote.host}
        header_up X-Forwarded-For {http.request.remote.host}
        header_up X-Forwarded-Proto {http.request.scheme}
        header_up X-Forwarded-Host {http.request.host}

        # Pass Tailscale user info for potential SSO integration
        header_up X-Webauth-User {http.request.header.Tailscale-User-Login}
        header_up X-Webauth-Name {http.request.header.Tailscale-User-Name}
        header_up X-Webauth-Email {http.request.header.Tailscale-User-Login}
        header_up Remote-User {http.request.header.Tailscale-User-Login}
      }
    '';
  };

  # Open firewall for Homarr
  networking.firewall.allowedTCPPorts = [ homarrPort ];
}
