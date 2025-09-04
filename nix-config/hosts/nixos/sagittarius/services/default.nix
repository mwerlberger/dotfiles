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
    ./jellyfin.nix
    ./vpn.nix
    ./sonarr.nix
    ./radarr.nix
    ./prowlarr.nix
    ./qbittorrent.nix
  ];
}
