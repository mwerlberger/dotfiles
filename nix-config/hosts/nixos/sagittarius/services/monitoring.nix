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
    enabledCollectors = [ "systemd" "zfs" "textfile" "filesystem" "loadavg" "meminfo" "netdev" "stat" ];
  };

  # 3. Enable Grafana for visualization

  services.grafana = {
    enable = true;
    settings = {
      "auth.proxy" = {
        enabled = true;
        header_name = "X-Webauth-User";
        header_property = "username";
        auto_sign_up = true;
        whitelist = "127.0.0.1";
        headers = "Name:X-Webauth-Name,Email:X-Webauth-Email";
        enable_login_token = false;
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

}
