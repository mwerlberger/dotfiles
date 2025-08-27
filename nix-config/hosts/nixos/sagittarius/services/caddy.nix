{ config, pkgs, lib, ... }:

{
  services.caddy = {
    enable = true;
    # Build Caddy with the Tailscale plugin.  This plugin lets Caddy obtain
    # and renew certificates from the local tailscaled daemon:contentReference[oaicite:4]{index=4}.
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
      # Root site (optional).
      "https://sagittarius.taildb4b48.ts.net" = {
        extraConfig = ''
          bind tailscale/sagittarius
          tls { get_certificate tailscale }
          tailscale_auth
          respond "sagittarius (tailscale) up" 200
        '';
      };

      "https://grafana.sagittarius.taildb4b48.ts.net" = {
        extraConfig = ''
          bind tailscale/grafana
          tls { get_certificate tailscale }
          tailscale_auth
          reverse_proxy http://127.0.0.1:3000
        '';
      };

      "https://prometheus.sagittarius.taildb4b48.ts.net" = {
        extraConfig = ''
          bind tailscale/prometheus
          tls { get_certificate tailscale }
          tailscale_auth
          reverse_proxy http://127.0.0.1:9090
        '';
      };

      # Immich/Photos site
      "https://photos.sagittarius.taildb4b48.ts.net" = {
        extraConfig = ''
          bind tailscale/photos
          tls { get_certificate tailscale }
          tailscale_auth
          reverse_proxy http://127.0.0.1:2283
        '';
      };
    };
  };

  # Allow Caddy to read the tailscale certificates by running tailscaled with
  # TS_PERMIT_CERT_UID=caddy.
  services.tailscale.permitCertUid = "caddy";
}
