{ config, pkgs, lib, ... }:

let
  # Immich must run at the root of a (sub)domain.
  # This host name will be used by Caddy to proxy requests and by Immich to
  # generate share links.  Adjust if you prefer another subdomain.
  immichHost = "sagittarius.taildb4b48.ts.net";
in
{
  services.immich = {
    enable = true;
    port = 2283;
    host = "127.0.0.1";
    
    settings = {
      # External URL where Immich is served; required for share links.
      server = {
        externalDomain = "https://sagittarius.taildb4b48.ts.net:8444";
      };

      # OAuth configuration for Google.  Note: Google does NOT allow the
      # app.immich:// scheme, so mobile OAuth won't work.
      oauth = {
        enabled      = true;
        issuerUrl    = "https://accounts.google.com";
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

    # Use secretsFile to provide OAuth secrets via environment variables
    secretsFile = "/run/immich/secrets.env";
  };

  # Create the secrets environment file with agenix secrets
  systemd.services.immich-secrets = {
    description = "Generate Immich secrets environment file";
    wantedBy = [ "immich-server.service" ];
    before = [ "immich-server.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      mkdir -p /run/immich
      cat > /run/immich/secrets.env << EOF
OAUTH_CLIENT_ID=$(cat ${config.age.secrets.google-oauth-client-id.path})
OAUTH_CLIENT_SECRET=$(cat ${config.age.secrets.google-oauth-client-secret.path})
EOF
      chmod 600 /run/immich/secrets.env
    '';
  };
}