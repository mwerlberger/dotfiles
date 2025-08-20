{ pkgs
, username
, ...
}:
{
  imports = [
    ./ssh.nix
    ./samba.nix
    ./monitoring.nix
    ./reverse-proxy.nix
  ];
}