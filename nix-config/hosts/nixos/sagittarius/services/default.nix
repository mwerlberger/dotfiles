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
    ./jellyfin.nix
    ./vpn-namespace.nix
    ./arr.nix
    ./qbittorrent.nix
    ./sabnzbd.nix
    ./homepage.nix
  ];
}
