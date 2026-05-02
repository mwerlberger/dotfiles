{ config
, pkgs
, username
, ...
}:
{
  # agenix: use host SSH key to decrypt secrets
  age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  # agenix secret providing CLOUDFLARE_API_TOKEN (as KEY=VALUE env file)
  # age.secrets.cloudflare-api-token = {
  #   file = ../../../secrets/cloudflare-api-token.age;
  #   mode = "0400";
  #   owner = "root";
  #   group = "root";
  # };

  age.secrets.tailscale-authkey = {
    file = ../../../secrets/tailscale-authkey.age; # adjust path
    mode = "0400";
    owner = "root";
    group = "root";
  };

  age.secrets.google-oauth-client-id = {
    file = ../../../secrets/google-oauth-client-id.age; # adjust path
    mode = "0440";
    owner = "root";
    group = "nas";
  };

  age.secrets.google-oauth-client-secret = {
    file = ../../../secrets/google-oauth-client-secret.age; # adjust path
    mode = "0440";
    owner = "root";
    group = "nas";
  };

  age.secrets.immich-oauth-env = {
    file = ../../../secrets/immich-oauth-env.age;
    mode = "0400";
    owner = "immich";
    group = "immich";
  };

  age.secrets.immich-config = {
    file = ../../../secrets/immich-config.json.age;
    mode = "0400";
    owner = "immich";
    group = "immich";
  };

  # Hardcover API token for rreading-glasses — format: "Bearer <token>"
  # Retrieve from: hardcover.app → Settings → API
  # Expires annually on Jan 1 — update and restart rreading-glasses.service.
  age.secrets.hardcover-token = {
    file = ../../../secrets/hardcover-token.age;
    mode = "0400";
    owner = "root";
    group = "root";
  };

  age.secrets.mullvad-zrh = {
    file = ../../../secrets/mullvad-zrh.age;
    mode = "0400";
    owner = "root";
    group = "root";
  };

  age.secrets.mullvad-privatekey-ch-zrh-wg-202 = {
    file = ../../../secrets/mullvad-privatekey-ch-zrh-wg-202.age;
    mode = "0400";
    owner = "root";
    group = "root";
  };

  # Restic repository password for the Hetzner Storage Box backup.
  # Losing this password = losing the backups. Keep an offline copy.
  age.secrets.restic-password = {
    file = ../../../secrets/restic-password.age;
    mode = "0400";
    owner = "root";
    group = "root";
  };

}
