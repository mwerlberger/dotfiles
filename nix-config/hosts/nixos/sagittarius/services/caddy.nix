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
      email admin+caddy@werlberger.org
    '';

    virtualHosts = {
      # Main host for various services
      "sagittarius.taildb4b48.ts.net" = {
        extraConfig = ''
          bind 100.119.78.108
          tls {
            get_certificate tailscale
          }
          respond "sagittarius (tailscale) up" 200 
        '';
      };
      # Promoetheus
      "sagittarius.taildb4b48.ts.net:8442" = {
        extraConfig = ''
          bind 100.119.78.108
          tls {
            get_certificate tailscale
          }
          reverse_proxy 127.0.0.1:9090
        '';
      };
      # Grafana
      "sagittarius.taildb4b48.ts.net:8443" = {
        extraConfig = ''
          bind 100.119.78.108
          tls {
            get_certificate tailscale
          }
          reverse_proxy 127.0.0.1:3000
          # respond "grafana host matched" 200
        '';
      };
      # Immich
      "sagittarius.taildb4b48.ts.net:8444" = {
        extraConfig = ''
          bind 100.119.78.108
          tls {
            get_certificate tailscale
          }
          reverse_proxy 127.0.0.1:2283
        '';
      };
      # add more services similarly
    };
  };

  # Allow Caddy to read the tailscale certificates by running tailscaled with
  # TS_PERMIT_CERT_UID=caddy.
  services.tailscale.permitCertUid = "caddy";
  # Ensure tailscaled is up before Caddy
  systemd.services.caddy.after = [ "tailscaled.service" ];
  systemd.services.caddy.requires = [ "tailscaled.service" ];
}
