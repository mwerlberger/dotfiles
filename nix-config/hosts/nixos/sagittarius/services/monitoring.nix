{ pkgs
, username
, ...
}:
let
  # node_exporter reads *.prom files from here; the restic services write their
  # health metrics into it (see services/restic.nix). Kept in sync by literal
  # path in both files.
  textfileDir = "/var/lib/node-exporter-textfile";
in
{
  # World-readable dir owned by root: restic (root) writes, node-exporter reads.
  systemd.tmpfiles.rules = [
    "d ${textfileDir} 0755 root root -"
  ];

  # 1. Enable Prometheus and configure it to scrape metrics from node_exporter
  services.prometheus = {
    enable = true;
    scrapeConfigs = [
      {
        job_name = "node";
        static_configs = [{
          targets = [ "localhost:9100" ];
        }];
      }
    ];
  };

  # 2. Enable the node_exporter to collect system metrics
  services.prometheus.exporters.node = {
    enable = true;
    enabledCollectors = [ "systemd" "zfs" "textfile" "filesystem" "loadavg" "meminfo" "netdev" "stat" ];
    # The textfile collector is inert without a directory to read from.
    extraFlags = [ "--collector.textfile.directory=${textfileDir}" ];
  };

  # 3. Enable Grafana for visualization

  services.grafana = {
    enable = true;
    provision = {
      enable = true;
      datasources.settings = {
        datasources = [
          {
            name = "Prometheus";
            uid = "prometheus";
            type = "prometheus";
            access = "proxy";
            url = "http://127.0.0.1:9090";
            isDefault = true;
          }
        ];
        # This host historically had Prometheus datasources with auto-generated
        # uids ("Prometheus" and a stray lowercase "prometheus"). Pinning uid
        # above collides with those on update ("data source not found"), so
        # purge them by name first; provisioning then re-inserts cleanly with
        # the stable uid. Safe/idempotent — nothing else owns this datasource.
        deleteDatasources = [
          { name = "Prometheus"; orgId = 1; }
          { name = "prometheus"; orgId = 1; }
        ];
      };
      dashboards.settings.providers = [
        {
          name = "nix-dashboards";
          options.path = "/etc/grafana-dashboards";
        }
      ];
    };
    settings = {
      # Grafana 26.05 removed the default secret_key. This is the previous
      # default — kept to preserve any existing DB-encrypted values. No
      # sensitive secrets are stored in this Grafana's DB (only an
      # unauthenticated localhost Prometheus datasource), so rotation is
      # not required.
      security.secret_key = "SW2YcwTIb9zpOOhoPsMm";

      "auth.proxy" = {
        enabled = true;
        header_name = "X-Webauth-User";
        header_property = "username";
        auto_sign_up = true;
        whitelist = "127.0.0.1";
        headers = "Name:X-Webauth-Name,Email:X-Webauth-Email";
        enable_login_token = false;
      };

      users = {
        # Set default role for new users
        default_role = "Admin";
        # Admin users
        admin_users = "manuel@werlberger.org";
      };

      server = {
        domain = "sagittarius.taildb4b48.ts.net";
        root_url = "https://sagittarius.taildb4b48.ts.net:8443/";
        http_addr = "127.0.0.1";
        http_port = 3000;
        serve_from_sub_path = false;
      };
    };
  };

  # Provisioned dashboard visualising the restic backup/check health metrics
  # emitted via the node_exporter textfile collector.
  environment.etc."grafana-dashboards/backups.json".source = ./dashboards/backups.json;

}
