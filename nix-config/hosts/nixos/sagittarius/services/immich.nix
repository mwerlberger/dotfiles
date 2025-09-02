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

  };

  # Create runtime directory and secrets file for Immich OAuth
  systemd.tmpfiles.rules = [
    "d /var/lib/immich-secrets 0750 ${config.services.immich.user} ${config.services.immich.group} -"
  ];

  systemd.services.immich-secrets = {
    description = "Generate Immich OAuth secrets";
    wantedBy = [ "immich-server.service" ];
    before = [ "immich-server.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      cat > /var/lib/immich-secrets/oauth.env << EOF
OAUTH_CLIENT_ID=$(cat ${config.age.secrets.google-oauth-client-id.path})
OAUTH_CLIENT_SECRET=$(cat ${config.age.secrets.google-oauth-client-secret.path})
EOF
      chown ${config.services.immich.user}:${config.services.immich.group} /var/lib/immich-secrets/oauth.env
      chmod 600 /var/lib/immich-secrets/oauth.env
    '';
  };

  # Configure immich-server to use the secrets environment file
  systemd.services.immich-server.serviceConfig.EnvironmentFile = "/var/lib/immich-secrets/oauth.env";
}