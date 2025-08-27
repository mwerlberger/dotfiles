{ pkgs
, username
, ...
}:
{ 
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
    enabledCollectors = [ "systemd" "zfs" ]; # Add other collectors as needed
    # To monitor drive temperatures, you may need to enable the textfile collector
    # and use a script that outputs metrics in the Prometheus format.
  };

  # 3. Enable Grafana for visualization
  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = "0.0.0.0";
        root_url = "https://grafana.sagittarius.taildb4b48.ts.net";
        serve_from_sub_path = false;
      };
    };
  };
}
