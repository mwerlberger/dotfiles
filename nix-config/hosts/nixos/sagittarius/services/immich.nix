{ config, pkgs, lib, ... }:

let
  # Immich must run at the root of a (sub)domain:contentReference[oaicite:3]{index=3}.
  # This host name will be used by Caddy to proxy requests and by Immich to
  # generate share links.  Adjust if you prefer another subdomain.
  immichHost = "sagittarius.taildb4b48.ts.net";
in
{
  services.immich = {
    enable = true;
    port = 2283;
    host = "127.0.0.1";
    # openFirewall = false;
    # settings.server.externalDomain = immichHost;
  };

  # No tmpfiles, no tailscale-cert service, no nginx configuration.
  # Caddy’s tailscale module handles TLS and proxying for the photos subdomain.

  # Provide a JSON settings file to Immich.  You can leave this null if you
  # prefer to configure OAuth via the web UI.
  settings = {
    # External URL where Immich is served; required for share links.
    server = {
      externalDomain = "https://sagittarius.taildb4b48.ts.net:8444";
    };

    # OAuth configuration for Google.  Note: Google does NOT allow the
    # app.immich:// scheme:contentReference[oaicite:2]{index=2}, so mobile OAuth won’t work.
    oauth = {
      enabled      = true;
      issuerUrl    = "https://accounts.google.com";
      clientId = config.age.secrets.google-oauth-client-id.path;
      clientSecret = config.age.secrets.google-oauth-client-secret.path;
      scope        = "openid email profile";
      autoRegister = true;
      # Do not set mobileRedirectUri here; Google cannot redirect to app.immich.
      buttonText   = "Login with Google";
    };

    # Optionally disable local password login to enforce SSO
    passwordLogin = {
      enabled = false;
    };
  };
}