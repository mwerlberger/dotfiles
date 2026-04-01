{ config, pkgs, lib, ... }:

let
  spliitHost = "sagittarius.taildb4b48.ts.net";
  spliitPort = 8449;
  spliitInternalPort = 3001;
in
{
  # PostgreSQL database for Spliit
  services.postgresql = {
    ensureDatabases = [ "spliit" ];
    ensureUsers = [
      {
        name = "spliit";
        ensureDBOwnership = true;
      }
    ];
    authentication = lib.mkAfter ''
      host spliit spliit 127.0.0.1/32 trust
    '';
  };

  # Spliit expense-sharing app (container, host network to reach PostgreSQL)
  virtualisation.oci-containers = {
    backend = "docker";
    containers.spliit = {
      image = "ghcr.io/spliit-app/spliit:latest";
      extraOptions = [ "--network=host" ];
      environment = {
        # Spliit uses Vercel-style Prisma config with separate pooled/direct URLs.
        # Both point to the same DB since we have no connection pooler.
        POSTGRES_PRISMA_URL = "postgresql://spliit@127.0.0.1/spliit";
        POSTGRES_URL_NON_POOLING = "postgresql://spliit@127.0.0.1/spliit";
        PORT = toString spliitInternalPort;
      };
    };
  };

  # Tailscale access
  services.caddy.virtualHosts."${spliitHost}:${toString spliitPort}" = {
    extraConfig = ''
      bind 100.119.78.108
      tls {
        get_certificate tailscale
      }
      tailscale_auth set_headers
      reverse_proxy 127.0.0.1:${toString spliitInternalPort} {
        header_up Host {http.request.host}
        header_up X-Real-IP {http.request.remote.host}
      }
    '';
  };

  # Local LAN access
  services.caddy.virtualHosts."192.168.1.206:${toString spliitPort}" = {
    extraConfig = ''
      bind 192.168.1.206
      tls internal
      reverse_proxy 127.0.0.1:${toString spliitInternalPort} {
        header_up Host {http.request.host}
        header_up X-Real-IP {http.request.remote.host}
      }
    '';
  };

  networking.firewall.allowedTCPPorts = [ spliitPort ];
}
