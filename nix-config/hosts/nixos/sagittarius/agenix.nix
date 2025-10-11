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
    owner = "immich";
    group = "nas";
  };

  age.secrets.mullvad-zrh = {
    file = ../../../secrets/mullvad-zrh.age;
    mode = "0400";
    owner = "root";
    group = "root";
  };

  age.secrets.mullvad-privatekey-ch-zrh-505 = {
    file = ../../../secrets/mullvad-privatekey-ch-zrh-505.age;
    mode = "0400";
    owner = "root";
    group = "root";
  };

}
