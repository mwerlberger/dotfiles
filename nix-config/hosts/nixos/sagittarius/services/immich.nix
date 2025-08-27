{ config, pkgs, lib, ... }:

let
  # Immich must run at the root of a (sub)domain:contentReference[oaicite:3]{index=3}.
  # This host name will be used by Caddy to proxy requests and by Immich to
  # generate share links.  Adjust if you prefer another subdomain.
  immichHost = "photos.sagittarius.taildb4b48.ts.net";
in
{
  services.immich = {
    enable = true;
    port = 2283;
    host = "127.0.0.1";
    openFirewall = false;
    settings.server.externalDomain = immichHost;
  };

  # No tmpfiles, no tailscale-cert service, no nginx configuration.
  # Caddy’s tailscale module handles TLS and proxying for the photos subdomain.

}