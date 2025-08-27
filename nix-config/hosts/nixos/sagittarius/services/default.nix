{ pkgs
, username
, ...
}:
{
  imports = [
    ./ssh.nix
    ./samba.nix
    ./nginx.nix
    ./monitoring.nix
    ./immich.nix
  ];
}
