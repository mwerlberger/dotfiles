{ pkgs
, username
, ...
}:
{
  imports = [
    ./ssh.nix
    ./samba.nix
    ./monitoring.nix
    # ./caddy.nix
    ./nginx.nix
  ];
}
