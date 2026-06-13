{ config, lib, ... }:

let
  audiobookshelfHost = "sagittarius.taildb4b48.ts.net";
  backendPort = 8000;
  externalPort = 8446;
in
{
  services.audiobookshelf = {
    enable = true;
    host = "127.0.0.1";
    port = backendPort;
  };

  users.users.${config.services.audiobookshelf.user}.extraGroups = [ "nas" ];

  services.caddy.virtualHosts."${audiobookshelfHost}:${toString externalPort}" = {
    extraConfig = ''
      bind 100.119.78.108
      tls {
        get_certificate tailscale
      }
      tailscale_auth
      reverse_proxy 127.0.0.1:${toString backendPort} {
        header_up Host {http.request.hostport}
        header_up X-Real-IP {http.request.remote.host}
        header_up X-Forwarded-For {http.request.remote.host}
        header_up X-Forwarded-Proto {http.request.scheme}
      }
    '';
  };

  services.caddy.virtualHosts."http://192.168.1.206:${toString externalPort}" = {
    extraConfig = ''
      bind 192.168.1.206
      reverse_proxy 127.0.0.1:${toString backendPort} {
        header_up Host {http.request.hostport}
        header_up X-Real-IP {http.request.remote.host}
        header_up X-Forwarded-For {http.request.remote.host}
        header_up X-Forwarded-Proto {http.request.scheme}
      }
    '';
  };

  networking.firewall.allowedTCPPorts = [ externalPort ];
}
