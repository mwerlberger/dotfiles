{ pkgs
, username
, ...
}:
{
  services.samba = {
    enable = true;
    settings = {
      # The name of your share as it appears on the network
      datalake = {
        path = "/data/lake";
        browseable = "yes";
        writable = "yes";
        "guest ok" = "no";
        # Replace with your actual user(s)
        "valid users" = [ "mw" ];

        # This part is crucial for ZFS!
        # It makes the .zfs/snapshot directory visible in the share.
        "vfs objects" = "zfs_fs";
      };
    };
  };
}
