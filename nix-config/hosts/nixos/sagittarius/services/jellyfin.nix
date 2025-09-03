{ config, pkgs, lib, ... }:

let
  # Jellyfin host configuration for reverse proxy
  jellyfinHost = "sagittarius.taildb4b48.ts.net";
in
{
  services.jellyfin = {
    enable = true;
    openFirewall = false; # We'll use reverse proxy instead
    dataDir = "/data/lake/media/jellyfin";
  };

  # Add jellyfin user to nas group for media directory access
  users.users.${config.services.jellyfin.user}.extraGroups = [ "nas" ];

  # Ensure media directory exists and has proper permissions
  systemd.tmpfiles.rules = [
    "d /data/lake/media/jellyfin 0770 jellyfin nas -"
  ];

  # Add reverse proxy configuration to Caddy
  services.caddy.virtualHosts."${jellyfinHost}:8445" = {
    extraConfig = ''
      bind 100.119.78.108
      tls {
        get_certificate tailscale
      }
      tailscale_auth
      reverse_proxy 127.0.0.1:8096 {
        header_up Host {http.request.host}
        header_up X-Real-IP {http.request.remote.host}
        header_up X-Forwarded-For {http.request.remote.host}
        header_up X-Forwarded-Proto {http.request.scheme}
      }
    '';
  };
}