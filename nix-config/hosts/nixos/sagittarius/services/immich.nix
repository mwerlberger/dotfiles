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
    mediaLocation = "/data/lake/photos/immich";

    settings = {
      # External URL where Immich is served; required for share links.
      server = {
        externalDomain = "https://sagittarius.taildb4b48.ts.net:8444";
      };

      # Optionally disable local password login to enforce SSO
      passwordLogin = {
        enabled = false;
      };
    };

    # OAuth configuration via environment variables (secrets provided via EnvironmentFile)
    environment = {
      OAUTH_ENABLED = "true";
      OAUTH_ISSUER_URL = "https://accounts.google.com";
      OAUTH_SCOPE = "openid email profile";
      OAUTH_AUTO_REGISTER = "true";
      OAUTH_BUTTON_TEXT = "Login with Google";
    };

  };

  # Add immich user to nas group for media directory access
  users.users.${config.services.immich.user}.extraGroups = [ "nas" ];

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
