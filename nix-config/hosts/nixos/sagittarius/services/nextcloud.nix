{ config, pkgs, pkgs-unstable, lib, ... }:

let
  # Nextcloud host configuration for reverse proxy
  nextcloudHost = "sagittarius.taildb4b48.ts.net";
  nextcloudPort = 8446;
  # Internal Nginx port (must not conflict with Caddy on port 80)
  nextcloudInternalPort = 8447;
in
{
  # Enable Redis for caching
  services.redis.servers.nextcloud = {
    enable = true;
    port = 6379;
    bind = "127.0.0.1";
  };

  services.nextcloud = {
    enable = true;

    # Use Nextcloud 32 from unstable channel
    package = pkgs-unstable.nextcloud32;

    # Host configuration
    hostName = nextcloudHost;

    # Use HTTPS (handled by Caddy reverse proxy)
    https = true;

    # Database configuration (PostgreSQL)
    database.createLocally = true;

    # Disable the app store since we manage apps via Nix
    appstoreEnable = false;

    # Basic configuration
    config = {
      dbtype = "pgsql";

      # Admin account - change these after first login!
      adminuser = "admin";
      adminpassFile = "/var/lib/nextcloud-secrets/admin-pass";
    };

    # Maximum upload size (also sets memory_limit, upload_max_filesize, post_max_size)
    maxUploadSize = "16G";

    # PHP settings for better performance
    phpOptions = {
      "opcache.interned_strings_buffer" = "16";
      "opcache.memory_consumption" = "256";
      "max_execution_time" = "3600";
    };

    # Enable Redis caching
    configureRedis = true;

    # Data directory on ZFS pool
    datadir = "/data/lake/nextcloud";

    # Additional settings
    settings = {
      # Default phone region
      default_phone_region = "CH";

      # Maintenance window (2 AM - 4 AM UTC)
      maintenance_window_start = 2;

      # Enable file locking
      filelocking.enabled = true;

      # Log level (0=Debug, 1=Info, 2=Warn, 3=Error, 4=Fatal)
      loglevel = 2;

      # Use HTTPS (handled by Caddy reverse proxy)
      overwriteprotocol = "https";

      # Force the host with port for proper redirects
      overwritehost = "${nextcloudHost}:${toString nextcloudPort}";
      overwritewebroot = "/";

      # Trust the reverse proxy
      trusted_proxies = [ "127.0.0.1" "::1" ];
    };

    # Auto-update apps
    autoUpdateApps.enable = true;
    autoUpdateApps.startAt = "05:00:00";
  };

  # Add nextcloud user to nas group for media directory access
  users.users.nextcloud.extraGroups = [ "nas" ];

  # Configure Nginx to listen on a custom port instead of 80
  services.nginx = {
    enable = true;
    virtualHosts.${nextcloudHost} = {
      listen = [
        { addr = "127.0.0.1"; port = nextcloudInternalPort; }
      ];
    };
  };

  # Ensure data directory exists with proper permissions
  systemd.tmpfiles.rules = [
    "d /data/lake/nextcloud 0770 nextcloud nas - -"
    "d /data/lake/nextcloud/config 0770 nextcloud nas - -"
    "d /var/lib/nextcloud-secrets 0750 root root - -"
  ];

  # Create initial admin password file
  # You should change this password after first login!
  systemd.services.nextcloud-init-password = {
    description = "Initialize Nextcloud admin password";
    wantedBy = [ "nextcloud-setup.service" ];
    before = [ "nextcloud-setup.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      if [ ! -f /var/lib/nextcloud-secrets/admin-pass ]; then
        echo "changeme123" > /var/lib/nextcloud-secrets/admin-pass
        chmod 600 /var/lib/nextcloud-secrets/admin-pass
        chown nextcloud:nextcloud /var/lib/nextcloud-secrets/admin-pass
      fi
    '';
  };

  # Add reverse proxy configuration to Caddy
  services.caddy.virtualHosts."${nextcloudHost}:${toString nextcloudPort}" = {
    extraConfig = ''
      bind 100.119.78.108
      tls {
        get_certificate tailscale
      }

      # Tailscale authentication - passes headers to backend
      tailscale_auth set_headers

      # Nextcloud-specific headers
      reverse_proxy 127.0.0.1:${toString nextcloudInternalPort} {
        header_up Host {http.request.host}
        header_up X-Real-IP {http.request.remote.host}

        # Pass Tailscale user info for SSO
        header_up Tailscale-User-Login {http.request.header.Tailscale-User-Login}
        header_up Tailscale-User-Name {http.request.header.Tailscale-User-Name}
      }

      # Handle .well-known redirects for CalDAV/CardDAV
      redir /.well-known/carddav /remote.php/dav 301
      redir /.well-known/caldav /remote.php/dav 301
      redir /.well-known/webfinger /index.php/.well-known/webfinger 301
      redir /.well-known/nodeinfo /index.php/.well-known/nodeinfo 301
    '';
  };

  # Local LAN access (optional - without Tailscale auth)
  services.caddy.virtualHosts."http://192.168.1.206:${toString nextcloudPort}" = {
    extraConfig = ''
      bind 192.168.1.206
      reverse_proxy 127.0.0.1:${toString nextcloudInternalPort} {
        header_up Host {http.request.host}
        header_up X-Real-IP {http.request.remote.host}
        header_up X-Forwarded-For {http.request.remote.host}
        header_up X-Forwarded-Proto {http.request.scheme}
        header_up X-Forwarded-Host {http.request.host}
      }

      # Handle .well-known redirects
      redir /.well-known/carddav /remote.php/dav 301
      redir /.well-known/caldav /remote.php/dav 301
    '';
  };

  # Open firewall for Nextcloud
  networking.firewall.allowedTCPPorts = [ nextcloudPort ];
}
