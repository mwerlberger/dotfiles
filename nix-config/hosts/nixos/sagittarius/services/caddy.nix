{ config, pkgs, lib, ... }:

{
  services.caddy = {
    enable = true;

    # Build Caddy with the Tailscale plugin - using latest commit
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/tailscale/caddy-tailscale@v0.0.0-20250508175905-642f61fea3cc" ];
      hash = "sha256-0GsjeeJnfLsJywWzWwJcCDk5wjTSBwzqMBY7iHjPQa8=";
    };

    globalConfig = ''
      email admin+tailscale@werlberger.org
      
      tailscale {
        auth_key {env.TS_AUTHKEY}
        ephemeral true
      }
    '';

    virtualHosts = {
      # Root site - bind to Tailscale network
      "https://sagittarius.taildb4b48.ts.net" = {
        extraConfig = ''
          bind tailscale/sagittarius
          
          tls {
            get_certificate tailscale
          }

          tailscale_auth
          respond "sagittarius (tailscale) up" 200
        '';
      };

      # Grafana site - bind to Tailscale network
      "https://grafana.sagittarius.taildb4b48.ts.net" = {
        extraConfig = ''
          bind tailscale/grafana
          
          tls {
            get_certificate tailscale
          }

          tailscale_auth
          reverse_proxy http://127.0.0.1:3000
        '';
      };

      # Prometheus site - bind to Tailscale network
      "https://prometheus.sagittarius.taildb4b48.ts.net" = {
        extraConfig = ''
          bind tailscale/prometheus
          
          tls {
            get_certificate tailscale
          }

          tailscale_auth
          reverse_proxy http://127.0.0.1:9090
        '';
      };
    };
  };

  # Allow Caddy to read Tailscale certs and provide environment variables
  services.tailscale.permitCertUid = "caddy";
  
  # Provide Tailscale auth key to Caddy service
  systemd.services.caddy.serviceConfig.EnvironmentFile = [
    config.age.secrets.tailscale-authkey.path
  ];
}
