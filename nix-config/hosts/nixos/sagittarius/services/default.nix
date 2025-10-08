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
    # ./sonarr.nix
    # ./radarr.nix
    # ./prowlarr.nix
    # ./qbittorrent.nix
    ./homepage.nix
  ];
}
