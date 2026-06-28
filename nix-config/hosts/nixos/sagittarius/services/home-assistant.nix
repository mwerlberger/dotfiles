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
  lanIp = "192.168.1.206";
  dataDir = "/data/lake/documents/homeassistant";
in
{
  services.home-assistant = {
    enable = true;

    # Config and state live on the ZFS "lake" pool (covered by restic backups).
    configDir = dataDir;

    config = {
      homeassistant = {
        name = "Home";
        # Approximate home coordinates (not sensitive). Adjust to taste.
        latitude = 47.3769;
        longitude = 8.5417;
        elevation = 408;

        unit_system = "metric";
        time_zone = "Europe/Zurich";

        # Allow password-less access from loopback and the Tailscale CGNAT range
        # (the UI sits behind Caddy + tailscale_auth), plus normal login.
        auth_providers = [
          {
            type = "trusted_networks";
            trusted_networks = [
              "127.0.0.1"
              "::1"
              "100.64.0.0/10" # Tailscale CGNAT range
            ];
            allow_bypass_login = true;
          }
          { type = "homeassistant"; }
        ];

        external_url = "https://${haHost}:${toString haPort}";
        internal_url = "http://127.0.0.1:${toString haInternalPort}";
      };

      # Pulls in the common set of integrations (frontend, zeroconf, etc.).
      default_config = { };

      # Web UI is fronted by Caddy, which terminates TLS and sets X-Forwarded-*.
      http = {
        server_host = "127.0.0.1";
        server_port = haInternalPort;
        use_x_forwarded_for = true;
        trusted_proxies = [
          "127.0.0.1"
          "::1"
        ];
      };

      # Expose Home Assistant's own entities (e.g. NAS sensors, a future second
      # Zigbee coordinator, scripts) into Apple Home via the HomeKit bridge.
      # Thread/Matter devices are already in Apple Home directly via the shared
      # Thread network and don't need this. Default port is 21063.
      homekit = [
        {
          name = "Home Assistant Bridge";
          advertise_ip = lanIp;
          filter.include_domains = [
            "light"
            "switch"
            "sensor"
            "binary_sensor"
            "climate"
            "cover"
            "lock"
          ];
        }
      ];

      prometheus = { };

      automation = "!include automations.yaml";
      script = "!include scripts.yaml";
      scene = "!include scenes.yaml";
    };

    # Integrations whose Python dependencies must be baked into the package.
    #   matter -> talks to services.matter-server (Matter controller)
    #   otbr/thread -> manage the local OpenThread Border Router (ZBT-2)
    #   homekit -> HomeKit bridge to Apple Home
    extraComponents = [
      "default_config"
      "met"
      "radio_browser"
      "matter"
      "otbr"
      "thread"
      "homekit"
    ];
  };

  # hass must be in the `nas` group to traverse /data/lake/documents (0770 mw:nas)
  # and reach its config dir, matching immich/jellyfin/nextcloud/paperless.
  users.users.hass.extraGroups = [ "nas" ];

  # Create the config dir on the ZFS pool.
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 hass hass - -"
  ];

  # Seed the UI-editable include files if absent. This can't be done with
  # tmpfiles `f` rules: systemd-tmpfiles refuses to write under ${dataDir}
  # because its parent (/data/lake/documents) is owned by a different user
  # ("unsafe path transition"). Doing it from preStart runs as hass inside the
  # config dir, which is allowed. Without these, HA drops into recovery mode.
  systemd.services.home-assistant.preStart = lib.mkAfter ''
    [ -e ${dataDir}/automations.yaml ] || echo "[]" > ${dataDir}/automations.yaml
    [ -e ${dataDir}/scenes.yaml ]      || echo "[]" > ${dataDir}/scenes.yaml
    [ -e ${dataDir}/scripts.yaml ]     || echo "{}" > ${dataDir}/scripts.yaml
  '';

  # Web UI over Tailscale (authenticated by tailscale_auth).
  services.caddy.virtualHosts."${haHost}:${toString haPort}" = {
    extraConfig = ''
      bind 100.119.78.108
      tls {
        get_certificate tailscale
      }
      tailscale_auth
      reverse_proxy 127.0.0.1:${toString haInternalPort} {
        header_up Host {http.request.host}
        header_up X-Real-IP {http.request.remote.host}
        header_up X-Forwarded-For {http.request.remote.host}
        header_up X-Forwarded-Proto {http.request.scheme}
      }
    '';
  };

  # Web UI over the LAN (Caddy internal CA).
  services.caddy.virtualHosts."${lanIp}:${toString haPort}" = {
    extraConfig = ''
      bind ${lanIp}
      tls internal
      reverse_proxy 127.0.0.1:${toString haInternalPort} {
        header_up Host {http.request.host}
        header_up X-Real-IP {http.request.remote.host}
        header_up X-Forwarded-For {http.request.remote.host}
        header_up X-Forwarded-Proto {http.request.scheme}
      }
    '';
  };
}
