{
  config,
  pkgs,
  lib,
  ...
}:

let
  paperlessHost = "sagittarius.taildb4b48.ts.net";
  paperlessPort = 8446;
  paperlessInternalPort = 28981;
in
{
  # Enable Redis for paperless-ngx task queue and caching
  services.redis.servers.paperless = {
    enable = true;
    port = 6380;
    bind = "127.0.0.1";
  };

  services.paperless = {
    enable = true;

    # Data directory on ZFS pool
    dataDir = "/data/lake/documents/paperless";
    mediaDir = "/data/lake/documents/paperless/media";

    # Listen address
    address = "127.0.0.1";
    port = paperlessInternalPort;

    # Use PostgreSQL database
    settings = {
      PAPERLESS_DBHOST = "/run/postgresql";
      PAPERLESS_DBNAME = "paperless";
      PAPERLESS_DBUSER = "paperless";

      # Redis configuration
      PAPERLESS_REDIS = "redis://127.0.0.1:6380";

      # Enable remote user authentication via Tailscale
      PAPERLESS_ENABLE_HTTP_REMOTE_USER = true;
      PAPERLESS_ENABLE_HTTP_REMOTE_USER_API = true;
      PAPERLESS_HTTP_REMOTE_USER_HEADER_NAME = "HTTP_X_REMOTE_USER";
      PAPERLESS_LOGOUT_REDIRECT_URL = "https://${paperlessHost}:${toString paperlessPort}";

      # Auto-create users from remote auth
      PAPERLESS_AUTO_LOGIN_USERNAME = "admin";

      # OCR settings
      PAPERLESS_OCR_LANGUAGE = "eng+deu"; # English and German
      PAPERLESS_OCR_MODE = "skip"; # skip, redo, force

      # Time zone
      PAPERLESS_TIME_ZONE = "Europe/Zurich";

      # URL for proper link generation
      PAPERLESS_URL = "https://${paperlessHost}:${toString paperlessPort}";

      # Admin email
      PAPERLESS_ADMIN_MAIL = "admin@werlberger.org";

      # Consumer settings
      PAPERLESS_CONSUMER_POLLING = 60; # Check for new documents every 60 seconds
      PAPERLESS_CONSUMER_DELETE_DUPLICATES = true;
      PAPERLESS_CONSUMER_RECURSIVE = true;

      # Filename formatting
      PAPERLESS_FILENAME_FORMAT = "{{ created_year }}/{{ correspondent }}/{{ created }}-{{ title }}";

      # Task workers
      PAPERLESS_TASK_WORKERS = 2;

      # Enable tika for better document parsing (optional)
      PAPERLESS_TIKA_ENABLED = false;
    };
  };

  # Create PostgreSQL database for paperless
  services.postgresql = {
    ensureDatabases = [ "paperless" ];
    ensureUsers = [
      {
        name = "paperless";
        ensureDBOwnership = true;
      }
    ];
  };

  # Add paperless user to nas group for potential shared media access
  users.users.paperless.extraGroups = [ "nas" ];

  # Ensure data directories exist with proper permissions
  systemd.tmpfiles.rules = [
    "d /data/lake/documents/paperless 0770 paperless nas - -"
    "d /data/lake/documents/paperless/media 0770 paperless nas - -"
    "d /data/lake/documents/paperless/consume 0770 paperless nas - -"
    "d /data/lake/documents/paperless/export 0770 paperless nas - -"
  ];

  # Open firewall for paperless
  networking.firewall.allowedTCPPorts = [ paperlessPort ];

  # Add reverse proxy configuration to Caddy
  services.caddy.virtualHosts."${paperlessHost}:${toString paperlessPort}" = {
    extraConfig = ''
      bind 100.119.78.108
      tls {
        get_certificate tailscale
      }
      # Tailscale authentication with remote user header
      tailscale_auth set_headers
      reverse_proxy 127.0.0.1:${toString paperlessInternalPort} {
        header_up Host {http.request.host}
        header_up X-Real-IP {http.request.remote.host}
        # Pass Tailscale user for remote auth
        header_up X-Remote-User {http.request.header.Tailscale-User-Login}
      }
    '';
  };

  # Paperless: Local LAN access
  services.caddy.virtualHosts."192.168.1.206:${toString paperlessPort}" = {
    extraConfig = ''
      bind 192.168.1.206
      tls internal  # Uses Caddy's internal CA for LAN
      reverse_proxy 127.0.0.1:${toString paperlessInternalPort} {
        header_up Host {http.request.host}
        header_up X-Real-IP {http.request.remote.host}
      }
    '';
  };
}
