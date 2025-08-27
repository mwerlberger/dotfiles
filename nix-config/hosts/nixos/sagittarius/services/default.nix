{ pkgs
, username
, ...
}:
{
  imports = [
    ./ssh.nix
    ./samba.nix
    ./caddy.nix
    ./monitoring.nix
    ./immich.nix
  ];
}
