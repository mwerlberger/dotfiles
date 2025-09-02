{ config, pkgs, lib, ... }:

{
  services.caddy = {
    enable = true;

    # Build Caddy with the Tailscale‑auth plugin (uses the system tailscaled).
    package = pkgs.caddy.withPlugins {
      plugins = [
        "go.akpain.net/caddy-tailscale-auth@v0.1.7"
      ];
      # Ask Nix to compute the vendor hash automatically; replace with the
      # real hash once you've run `nix build`.
      hash = "sha256-e3WZoIVlRxEABd94tgb2tRMj4XEL7+2yF/olM/O+v5w=";
    };

    globalConfig = ''
      email admin+caddy@werlberger.org
    '';

    virtualHosts = {
      # Public status page
      "sagittarius.taildb4b48.ts.net" = {
        extraConfig = ''
          bind 100.119.78.108
          tls {
            get_certificate tailscale
          }
          respond "sagittarius (tailscale) up" 200
        '';
      };
      # Prometheus
      "sagittarius.taildb4b48.ts.net:8442" = {
        extraConfig = ''
          bind 100.119.78.108
          tls {
            get_certificate tailscale
          }
          reverse_proxy 127.0.0.1:9090
        '';
      };
      # Grafana with Tailscale auth
      "sagittarius.taildb4b48.ts.net:8443" = {
        extraConfig = ''
          bind 100.119.78.108
          tls {
            get_certificate tailscale
          }
          # Enforce that requests come from your tailnet and capture the user identity
          tailscale_auth set_headers
          reverse_proxy 127.0.0.1:3000 {
            header_up X-Webauth-User {http.request.header.Tailscale-User-Login}
            header_up X-Webauth-Name {http.request.header.Tailscale-User-Name}
            header_up X-Webauth-Email {http.request.header.Tailscale-User-Login}
          }
        '';
      };
      # Immich
      "sagittarius.taildb4b48.ts.net:8444" = {
        extraConfig = ''
          bind 100.119.78.108
          tls {
            get_certificate tailscale
          }
          tailscale_auth
          reverse_proxy 127.0.0.1:2283 {
            # forward the usual proxy headers Immich expects
            header_up Host {http.request.host}
            header_up X-Real-IP {http.request.remote.host}
            header_up X-Forwarded-For {http.request.remote.host}
            header_up X-Forwarded-Proto {http.request.scheme}
          }
        '';
      };
    };
  };

  # Let Caddy read Tailscale certificates.
  services.tailscale.permitCertUid = "caddy";
  # Make sure tailscaled is running before Caddy starts.
  systemd.services.caddy.after = [ "tailscaled.service" ];
  systemd.services.caddy.requires = [ "tailscaled.service" ];

  # Make the caddy user a member of the tailscale group so it can access the LocalAPI socket.
  users.users.caddy.extraGroups = [ "tailscale" ];
}
