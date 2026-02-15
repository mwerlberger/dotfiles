{ config, pkgs, lib, ... }:

let
  pkgs-navidrome = import (builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/0358ff3.tar.gz";
    sha256 = "0jc67f1jgbdpqqsjag8wfsv6nqi415msi106l1zx3inyqi8jiz58";
  }) { system = pkgs.system; };
in {
  # Navidrome music streaming server
  services.navidrome = {
    enable = true;
    package = pkgs-navidrome.navidrome;
    settings = {
      Address = "127.0.0.1";
      Port = 4534;
      MusicFolder = "/data/lake/media/music";
      DataFolder = "/var/lib/navidrome";
      CacheFolder = "/var/cache/navidrome";

      # Reverse proxy authentication - bypasses login from trusted sources
      ReverseProxyUserHeader = "Remote-User";
      ReverseProxyWhitelist = "127.0.0.0/8";
    };
  };

  # Add navidrome user to nas group for music access
  users.users.navidrome.extraGroups = [ "nas" ];

  # Ensure data directories exist with proper permissions
  systemd.tmpfiles.rules = [
    "d /var/lib/navidrome 0770 navidrome navidrome -"
    "d /var/cache/navidrome 0770 navidrome navidrome -"
  ];

  # Reverse proxy configuration (accessible via Tailscale)
  # Note: Caddy handles HTTPS (via Tailscale cert), backend connection is HTTP
  services.caddy.virtualHosts."sagittarius.taildb4b48.ts.net:4533" = {
    extraConfig = ''
      tls {
        get_certificate tailscale
      }
      tailscale_auth set_headers
      reverse_proxy http://127.0.0.1:4534 {
        header_up Host {http.request.host}
        header_up X-Real-IP {http.request.remote.host}
        header_up X-Forwarded-For {http.request.remote.host}
        header_up X-Forwarded-Proto {http.request.scheme}
        header_up X-Webauth-User {http.request.header.Tailscale-User-Login}
        header_up X-Webauth-Name {http.request.header.Tailscale-User-Name}
        header_up X-Webauth-Email {http.request.header.Tailscale-User-Login}
        header_up Remote-User {http.request.header.Tailscale-User-Login}
      }
    '';
  };
}
