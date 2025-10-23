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
    ./postgresql.nix
    ./immich.nix
    ./jellyfin.nix
    # ./nextcloud.nix
    # ./pydio-cells.nix  # Docker version
    # ./pydio-cells-native.nix  # Native binary version
    ./vpn-namespace.nix
    ./arr.nix
    ./qbittorrent.nix
    ./sabnzbd.nix
    ./navidrome.nix
    ./homepage.nix
  ];
}
