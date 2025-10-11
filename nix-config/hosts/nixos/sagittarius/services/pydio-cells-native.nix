{ config, pkgs, lib, ... }:

let
  # Pydio Cells host configuration for reverse proxy
  pydioHost = "sagittarius.taildb4b48.ts.net";
  pydioPort = 8448;
  pydioInternalPort = 8081;

  # Pydio Cells version
  pydioVersion = "4.4.11";

  # Download Pydio Cells binary
  pydio-cells = pkgs.stdenv.mkDerivation {
    pname = "pydio-cells";
    version = pydioVersion;

    src = pkgs.fetchurl {
      url = "https://download.pydio.com/pub/cells/release/${pydioVersion}/linux-amd64/cells";
      sha256 = "sha256-vRoUXqvxK6MmMSI9KbiHThDkxOCQYeLyT4p4arquyK4=";
    };

    dontUnpack = true;
    dontBuild = true;

    installPhase = ''
      mkdir -p $out/bin
      cp $src $out/bin/cells
      chmod +x $out/bin/cells
    '';

    meta = with lib; {
      description = "Pydio Cells - Modern file sharing platform";
      homepage = "https://pydio.com";
      license = licenses.agpl3Plus;
      platforms = platforms.linux;
    };
  };

in
{
  # Enable MariaDB for Pydio Cells
  services.mysql = {
    enable = true;
    package = pkgs.mariadb;
    ensureDatabases = [ "pydio_cells" ];
    ensureUsers = [
      {
        name = "pydio";
        ensurePermissions = {
          "pydio_cells.*" = "ALL PRIVILEGES";
        };
      }
    ];
  };

  # Create pydio user and group
  users.users.pydio = {
    isSystemUser = true;
    group = "pydio";
    extraGroups = [ "nas" ];
    description = "Pydio Cells service user";
    home = "/var/lib/pydio-cells";
    createHome = true;
  };

  users.groups.pydio = {};

  # Create directories with proper permissions
  systemd.tmpfiles.rules = [
    "d /var/lib/pydio-cells 0750 pydio pydio - -"
    "d /data/lake/pydio-cells 0770 pydio nas - -"
  ];

  # Pydio Cells service
  systemd.services.pydio-cells = {
    description = "Pydio Cells - Modern file sharing platform";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" "zfs-mount.service" ];
    wants = [ "network-online.target" ];

    environment = {
      CELLS_WORKING_DIR = "/var/lib/pydio-cells";
      CELLS_BIND = "127.0.0.1:${toString pydioInternalPort}";
      CELLS_EXTERNAL = "https://${pydioHost}:${toString pydioPort}";
      CELLS_NO_TLS = "1";
    };

    serviceConfig = {
      Type = "simple";
      User = "pydio";
      Group = "pydio";
      ExecStart = "${pydio-cells}/bin/cells start";
      Restart = "on-failure";
      RestartSec = "10s";

      # Security hardening
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [
        "/var/lib/pydio-cells"
        "/data/lake/pydio-cells"
      ];
      ReadOnlyPaths = [
        "/data/lake/media"
      ];
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
  # services.caddy.virtualHosts."http://192.168.1.206:${toString pydioPort}" = {
  #   extraConfig = ''
  #     bind 192.168.1.206
  #     reverse_proxy 127.0.0.1:${toString pydioInternalPort} {
  #       header_up Host {http.request.host}
  #       header_up X-Real-IP {http.request.remote.host}
  #       header_up X-Forwarded-For {http.request.remote.host}
  #       header_up X-Forwarded-Proto {http.request.scheme}
  #       header_up X-Forwarded-Host {http.request.host}
  #     }
  #   '';
  # };

  # Open firewall for Pydio Cells
  networking.firewall.allowedTCPPorts = [ pydioPort ];
}
