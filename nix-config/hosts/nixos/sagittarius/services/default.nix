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
    ./home-assistant.nix
    ./openthread-border-router.nix
    ./nextcloud.nix
    # ./pydio-cells.nix  # Docker version
    # ./pydio-cells-native.nix  # Native binary version
    ./vpn-namespace.nix
    ./arr.nix
    ./bindery.nix
    ./qbittorrent.nix
    ./sabnzbd.nix
    ./navidrome.nix
    ./audiobookshelf.nix
    ./homepage.nix
    ./homarr.nix
    ./spliit.nix
    ./firefly-iii.nix
    ./restic.nix
  ];
}
