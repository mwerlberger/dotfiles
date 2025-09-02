{ pkgs
, username
, ...
}:
{
  imports = [
    ./ssh.nix
    ./samba.nix
    # ./oidc.nix
    ./caddy.nix
    ./monitoring.nix
    ./immich.nix
  ];
}
