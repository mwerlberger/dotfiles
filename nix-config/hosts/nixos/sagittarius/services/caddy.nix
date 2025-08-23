{ config, pkgs, lib, ... }:

{
  services.caddy = {
    enable = true;

    # Build Caddy with the tailscale plugin
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/mwerlberger/caddy-tailscale@v0.0.2" ];
      hash = "sha256-I22/U6N2rEjorZA+tiVCxh7SIbmXtskSSfhjHMrIEqI=";
    };

    globalConfig = ''
      email admin+tailscale@werlberger.org
      tailscale
    '';

virtualHosts = {
      "sagittarius.taildb4b48.ts.net" = {
        extraConfig = ''
          tls {
            get_certificate tailscale
          }

          @root path /
          respond @root "sagittarius (tailscale) up" 200

          # route /grafana* {
          #   tailscale {
          #     # Optionally restrict to specific users
          #     # users user1@ts.net,user2@ts.net
          #   }
          #   reverse_proxy localhost:3000
          # }

          # @grafana path /grafana*
          # handle @grafana {
          #   uri strip_prefix /grafana
          #   reverse_proxy http://127.0.0.1:3000
          # }

          # @prom path /prom* /prometheus*
          # handle @prom {
          #   uri strip_prefix /prom
          #   reverse_proxy http://127.0.0.1:9090
          # }
        '';
      };
        "grafana.sagittarius.taildb4b48.ts.net" = {
          extraConfig = ''
            tls {
              get_certificate tailscale
            }
            tailscale {
              # Optionally restrict to specific users
              # users user1@ts.net,user2@ts.net
            }
            reverse_proxy http://127.0.0.1:3000
          '';
        };
    };
  };

  # allow caddy to read tailscale certs
  services.tailscale.permitCertUid = "caddy";
}