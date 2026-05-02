let
  # Host SSH public key (sagittarius)
  sagittarius = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOgCTwCwDXw8HFc/Oo5mSPYXfTc4EV2q270n6wn6FDep";
  # User SSH public key
  mw = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID/AOeEzrs+tZWSMXDSHbBQDmrpN6CDsm8DpDisMhFq1";

  allKeys = [ sagittarius mw ];
in
{
  "secrets/cloudflare-api-token.age".publicKeys = allKeys;
  "secrets/tailscale-authkey.age".publicKeys = allKeys;
  "secrets/google-oauth-client-id.age".publicKeys = allKeys;
  "secrets/google-oauth-client-secret.age".publicKeys = allKeys;
  "secrets/immich-oauth-env.age".publicKeys = allKeys;
  "secrets/immich-config.json.age".publicKeys = allKeys;
  "secrets/hardcover-token.age".publicKeys = allKeys;
  "secrets/mullvad-zrh.age".publicKeys = allKeys;
  "secrets/mullvad-privatekey-ch-zrh-wg-202.age".publicKeys = allKeys;
  "secrets/restic-password.age".publicKeys = allKeys;
}
