{ pkgs
, username
, ...
}:
{
  imports = [
    ./ssh.nix
    ./samba.nix
    ./nfs.nix
    ./caddy.nix
    ./monitoring.nix
    ./postgresql.nix
    ./immich.nix
    ./jellyfin.nix
    ./paperless.nix
    #./home-assistant.nix
    ./nextcloud.nix
    # ./pydio-cells.nix  # Docker version
    # ./pydio-cells-native.nix  # Native binary version
    ./vpn-namespace.nix
    ./arr.nix
    ./rreading-glasses.nix
    # ./bookshelf.nix  # disabled: mkYarnPackage removed in nixpkgs 26.05, migrate to yarn hooks
    ./qbittorrent.nix
    ./sabnzbd.nix
    ./navidrome.nix
    ./audiobookshelf.nix
    ./homepage.nix
    ./homarr.nix
    ./spliit.nix
    ./restic.nix
  ];
}
