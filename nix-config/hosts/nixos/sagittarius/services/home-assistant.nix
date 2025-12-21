{
  config,
  pkgs,
  lib,
  ...
}:

let
  haHost = "sagittarius.taildb4b48.ts.net";
  haPort = 8123;
  haInternalPort = 8123;
  dataDir = "/data/lake/documents/homeassistant";
in
{
  services.home-assistant = {
    enable = true;

    # Use custom data directory on ZFS pool
    config = {
      homeassistant = {
        name = "Home";
        # Latitude and longitude for your location (update these)
        latitude = "!secret latitude";
        longitude = "!secret longitude";
        elevation = "!secret elevation";

        unit_system = "metric";
        time_zone = "Europe/Zurich";

        # Trust reverse proxy headers from Caddy
        auth_providers = [
          {
            type = "trusted_networks";
            trusted_networks = [
              "127.0.0.1"
              "::1"
              "100.64.0.0/10"  # Tailscale CGNAT range
            ];
            trusted_users = {
              "127.0.0.1" = [ ];
            };
            allow_bypass_login = true;
          }
          {
            type = "homeassistant";
          }
        ];

        # External and internal URLs
        external_url = "https://${haHost}:${toString haPort}";
        internal_url = "http://127.0.0.1:${toString haInternalPort}";
      };

      # Enable useful default integrations
      default_config = { };

      # HTTP configuration for reverse proxy
      http = {
        server_host = "127.0.0.1";
        server_port = haInternalPort;
        use_x_forwarded_for = true;
        trusted_proxies = [
          "127.0.0.1"
          "::1"
        ];
      };

      # MQTT integration (connects to local Mosquitto)
      mqtt = {
        broker = "127.0.0.1";
        port = 1883;
        discovery = true;
        discovery_prefix = "homeassistant";
      };

      # Enable Prometheus metrics
      prometheus = { };

      # Basic automations and scripts
      automation = "!include automations.yaml";
      script = "!include scripts.yaml";
      scene = "!include scenes.yaml";
    };

    # Custom components/integrations via HACS or manual install
    extraComponents = [
      "mqtt"
      "esphome"
      "met"
      "radio_browser"
    ];

    # Allow Home Assistant to access USB devices for Zigbee
    extraPackages = python3Packages: with python3Packages; [
      psycopg2  # PostgreSQL support (if needed later)
    ];

    # Use custom configuration directory
    configDir = dataDir;
  };

  # Mosquitto MQTT broker for IoT devices
  services.mosquitto = {
    enable = true;
    listeners = [
      {
        address = "127.0.0.1";
        port = 1883;
        users = {
          homeassistant = {
            acl = [ "readwrite #" ];
            hashedPassword = "$7$101$m8Q8FqJ7kJ7J8Q8J$J8Q8J8Q8J8Q8J8Q8J8Q8J8Q8J8Q8J8Q8";  # Change this
          };
        };
        settings = {
          allow_anonymous = true;  # For local network only
        };
      }
    ];
  };

  # Zigbee2MQTT for Zigbee device support
  services.zigbee2mqtt = {
    enable = true;
    settings = {
      homeassistant = true;  # Enable Home Assistant integration
      permit_join = false;   # Disable joining by default (enable when pairing)

      mqtt = {
        base_topic = "zigbee2mqtt";
        server = "mqtt://127.0.0.1:1883";
        user = "homeassistant";
        password = "!secret mqtt_password";
      };

      serial = {
        # Update this path to match your Zigbee adapter
        # Common paths: /dev/ttyUSB0, /dev/ttyACM0, /dev/serial/by-id/...
        port = "/dev/ttyUSB0";
      };

      frontend = {
        port = 8080;
        host = "127.0.0.1";
      };

      advanced = {
        log_level = "info";
        pan_id = 6754;
        channel = 11;
        network_key = "GENERATE";  # Will auto-generate on first run
      };
    };
  };

  # Ensure data directories exist with proper permissions
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 hass hass - -"
    "d ${dataDir}/automations.yaml 0640 hass hass - -"
    "d ${dataDir}/scripts.yaml 0640 hass hass - -"
    "d ${dataDir}/scenes.yaml 0640 hass hass - -"
  ];

  # Create initial empty YAML files if they don't exist
  system.activationScripts.homeAssistantConfig = ''
    if [ ! -f ${dataDir}/automations.yaml ]; then
      echo "[]" > ${dataDir}/automations.yaml
      chown hass:hass ${dataDir}/automations.yaml
    fi
    if [ ! -f ${dataDir}/scripts.yaml ]; then
      echo "{}" > ${dataDir}/scripts.yaml
      chown hass:hass ${dataDir}/scripts.yaml
    fi
    if [ ! -f ${dataDir}/scenes.yaml ]; then
      echo "[]" > ${dataDir}/scenes.yaml
      chown hass:hass ${dataDir}/scenes.yaml
    fi
    if [ ! -f ${dataDir}/secrets.yaml ]; then
      cat > ${dataDir}/secrets.yaml << 'EOF'
# Home Assistant Secrets
latitude: 47.3769
longitude: 8.5417
elevation: 408
mqtt_password: changeme
EOF
      chown hass:hass ${dataDir}/secrets.yaml
      chmod 600 ${dataDir}/secrets.yaml
    fi
  '';

  # Open firewall for Home Assistant
  networking.firewall.allowedTCPPorts = [ haPort ];

  # Add reverse proxy configuration to Caddy - Tailscale access
  services.caddy.virtualHosts."${haHost}:${toString haPort}" = {
    extraConfig = ''
      bind 100.119.78.108
      tls {
        get_certificate tailscale
      }
      # Tailscale authentication
      tailscale_auth
      reverse_proxy 127.0.0.1:${toString haInternalPort} {
        header_up Host {http.request.host}
        header_up X-Real-IP {http.request.remote.host}
        header_up X-Forwarded-For {http.request.remote.host}
        header_up X-Forwarded-Proto {http.request.scheme}
      }
    '';
  };

  # Home Assistant: Local LAN access
  services.caddy.virtualHosts."192.168.1.206:${toString haPort}" = {
    extraConfig = ''
      bind 192.168.1.206
      tls internal  # Uses Caddy's internal CA for LAN
      reverse_proxy 127.0.0.1:${toString haInternalPort} {
        header_up Host {http.request.host}
        header_up X-Real-IP {http.request.remote.host}
        header_up X-Forwarded-For {http.request.remote.host}
        header_up X-Forwarded-Proto {http.request.scheme}
      }
    '';
  };

  # Allow hass user to access USB devices for Zigbee adapter
  users.users.hass.extraGroups = [ "dialout" "tty" ];

  # udev rules for common Zigbee adapters
  services.udev.extraRules = ''
    # ConBee/RaspBee
    SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6015", SYMLINK+="zigbee", MODE="0660", GROUP="dialout"
    # CC2531
    SUBSYSTEM=="tty", ATTRS{idVendor}=="0451", ATTRS{idProduct}=="16a8", SYMLINK+="zigbee", MODE="0660", GROUP="dialout"
    # Sonoff Zigbee 3.0 USB Dongle Plus
    SUBSYSTEM=="tty", ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="55d4", SYMLINK+="zigbee", MODE="0660", GROUP="dialout"
  '';
}
