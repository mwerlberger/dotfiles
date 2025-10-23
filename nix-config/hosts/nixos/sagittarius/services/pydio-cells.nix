{ config, pkgs, lib, ... }:

let
  # Pydio Cells host configuration for reverse proxy
  pydioHost = "sagittarius.taildb4b48.ts.net";
  pydioPort = 8448;
  # Internal Pydio port
  pydioInternalPort = 8081;
in
{
  # Enable Docker
  virtualisation.docker.enable = true;

  # Add necessary users to docker group
  users.users.mw.extraGroups = [ "docker" ];

  # Create directories with proper permissions
  systemd.tmpfiles.rules = [
    "d /data/lake/pydio-cells 0770 mw nas - -"
    "d /data/lake/pydio-cells/data 0770 mw nas - -"
    "d /data/lake/pydio-cells/db 0770 mw nas - -"
  ];

  # Pydio Cells Docker container via systemd
  systemd.services.pydio-cells = {
    description = "Pydio Cells - Modern file sharing platform";
    wantedBy = [ "multi-user.target" ];
    after = [ "docker.service" "network-online.target" "zfs-mount.service" ];
    requires = [ "docker.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = [
        # Pull the latest image
        "${pkgs.docker}/bin/docker pull pydio/cells:latest"
        # Remove old container if it exists
        "-${pkgs.docker}/bin/docker rm -f pydio-cells"
      ];
      ExecStart = ''
        ${pkgs.docker}/bin/docker run -d \
          --name pydio-cells \
          --restart unless-stopped \
          -p 127.0.0.1:${toString pydioInternalPort}:8080 \
          -v /data/lake/pydio-cells/data:/var/cells \
          -v /data/lake/media:/media:ro \
          -e CELLS_BIND=0.0.0.0:8080 \
          -e CELLS_EXTERNAL=https://${pydioHost}:${toString pydioPort} \
          -e CELLS_NO_TLS=1 \
          pydio/cells:latest
      '';
      ExecStop = "${pkgs.docker}/bin/docker stop pydio-cells";
    };
  };

  # Add reverse proxy configuration to Caddy
  services.caddy.virtualHosts."${pydioHost}:${toString pydioPort}" = {
    extraConfig = ''
      bind 100.119.78.108
      tls {
        get_certificate tailscale
      }

      # Tailscale authentication
      tailscale_auth set_headers

      # Pydio Cells reverse proxy
      reverse_proxy 127.0.0.1:${toString pydioInternalPort} {
        header_up Host {http.request.host}
        header_up X-Real-IP {http.request.remote.host}
        header_up X-Forwarded-For {http.request.remote.host}
        header_up X-Forwarded-Proto {http.request.scheme}
        header_up X-Forwarded-Host {http.request.host}

        # Pass Tailscale user info
        header_up Tailscale-User-Login {http.request.header.Tailscale-User-Login}
        header_up Tailscale-User-Name {http.request.header.Tailscale-User-Name}
      }
    '';
  };

  # Local LAN access (optional - without Tailscale auth)
  services.caddy.virtualHosts."http://192.168.1.206:${toString pydioPort}" = {
    extraConfig = ''
      bind 192.168.1.206
      reverse_proxy 127.0.0.1:${toString pydioInternalPort} {
        header_up Host {http.request.host}
        header_up X-Real-IP {http.request.remote.host}
        header_up X-Forwarded-For {http.request.remote.host}
        header_up X-Forwarded-Proto {http.request.scheme}
        header_up X-Forwarded-Host {http.request.host}
      }
    '';
  };

  # Open firewall for Pydio Cells
  networking.firewall.allowedTCPPorts = [ pydioPort ];
}
