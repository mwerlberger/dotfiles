{ config
, pkgs
, pkgs-unstable
, lib
, ...
}:

let
  # Immich must run at the root of a (sub)domain.
  # This host name will be used by Caddy to proxy requests and by Immich to
  # generate share links.  Adjust if you prefer another subdomain.
  immichHost = "sagittarius.taildb4b48.ts.net";
in
{
  services.immich = {
    package = pkgs-unstable.immich;
    enable = true;
    port = 2283;
    host = "127.0.0.1";
    mediaLocation = "/data/lake/photos/immich";

    # Use config file instead of inline settings
    # Set settings to null to disable config generation via NixOS module
    settings = null;

    # Point Immich to the config file managed by agenix
    environment = {
      IMMICH_CONFIG_FILE = config.age.secrets.immich-config.path;
    };
  };

  # Add immich user to nas group for media directory access
  users.users.${config.services.immich.user}.extraGroups = [ "nas" ];

  # Configure systemd service to set proper group ownership and permissions
  # Override the restrictive default UMask (0077) to allow group access
  systemd.services.immich-server.serviceConfig = {
    # Set umask so new files are group-readable and group-writable (umask 002 = rw-rw-r--)
    UMask = lib.mkForce "0002";
  };

  # Ensure media directory has correct group ownership
  systemd.tmpfiles.rules = [
    "d ${config.services.immich.mediaLocation} 0775 ${config.services.immich.user} nas - -"
    "Z ${config.services.immich.mediaLocation} 0775 ${config.services.immich.user} nas - -"
  ];
}
