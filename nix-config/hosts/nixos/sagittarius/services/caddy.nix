{ pkgs, config, lib, ... }:
let
  # agenix-provided env file containing: CLOUDFLARE_API_TOKEN=...
  # Kept for later use, but not used while Cloudflare is disabled
  cfEnvFile = config.age.secrets.cloudflare-api-token.path or null;

  # Disabled (kept for later): original Cloudflare-backed public vhosts
  cfDisabledVirtualHosts = {
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
    "https://grafana.sagittarius.werlberger.org" = {
      extraConfig = ''
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
        }
        reverse_proxy http://127.0.0.1:3000
      '';
    };
    "https://prom.sagittarius.werlberger.org" = {
      extraConfig = ''
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
        }
        reverse_proxy http://127.0.0.1:9090
      '';
    };
  };
in
{
  services.caddy = {
    enable = true;

    # Build Caddy with Tailscale plugin to issue TLS from Tailscale
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/mwerlberger/caddy-tailscale@v0.0.2" ];
      # First build will fail with a hash mismatch and print the correct sha256; replace this value then.
      hash = "sha256-I22/U6N2rEjorZA+tiVCxh7SIbmXtskSSfhjHMrIEqI=";
    };

    # Global options: set contact email (unused by Tailscale certs) and ensure plugin order
    globalConfig = ''
      email admin+tailscale@werlberger.org
      order tls.get_certificate tailscale
    '';

    # Tailscale-only access: single listener on :443, certs via Tailscale, path-based routing
    virtualHosts = {
      "https://:443" = {
        extraConfig = ''
          tls {
            get_certificate tailscale
          }

          # Health root
          @root path /
          respond @root "sagittarius (tailscale) up" 200

          # Grafana at /grafana
          @grafana path /grafana* 
          handle @grafana {
            uri strip_prefix /grafana
            reverse_proxy http://127.0.0.1:3000
          }

          # Prometheus at /prom
          @prom path /prom* /prometheus*
          handle @prom {
            uri strip_prefix /prom
            reverse_proxy http://127.0.0.1:9090
          }
        '';
      };
    };
  };

  # Cloudflare environment not applied while disabled
  # systemd.services.caddy.serviceConfig.EnvironmentFile = cfEnvFile;
}
