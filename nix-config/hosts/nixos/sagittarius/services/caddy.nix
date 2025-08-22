{ pkgs, config, ... }:
let
  # agenix-provided env file containing: CLOUDFLARE_API_TOKEN=...
  cfEnvFile = config.age.secrets.cloudflare-api-token.path or null;
in
{
  services.caddy = {
    enable = true;

    # Build Caddy with Cloudflare DNS provider for ACME DNS-01
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/caddy-dns/cloudflare@v0.2.1" ];
      hash = "sha256-S1JN7brvH2KIu7DaDOH1zij3j8hWLLc0HdnUc+L89uU=";
    };

    # Global contact for ACME
    globalConfig = ''
      email admin+acme@werlberger.org
    '';

    virtualHosts = {
      # Base host – simple health page
      "https://sagittarius.werlberger.org" = {
        extraConfig = ''
          tls {
            dns cloudflare {env.CLOUDFLARE_API_TOKEN}
          }
          encode zstd gzip
          @root path /
          respond @root "sagittarius up" 200
        '';
      };

      # Grafana reverse proxy
      "https://grafana.sagittarius.werlberger.org" = {
        extraConfig = ''
          tls {
            dns cloudflare {env.CLOUDFLARE_API_TOKEN}
          }
          reverse_proxy http://127.0.0.1:3000
        '';
      };

      # Prometheus reverse proxy
      "https://prom.sagittarius.werlberger.org" = {
        extraConfig = ''
          tls {
            dns cloudflare {env.CLOUDFLARE_API_TOKEN}
          }
          reverse_proxy http://127.0.0.1:9090
        '';
      };
    };
  };

  # Provide Cloudflare token to Caddy from the agenix secret (KEY=VALUE file)
  systemd.services.caddy.serviceConfig.EnvironmentFile = cfEnvFile;
}
