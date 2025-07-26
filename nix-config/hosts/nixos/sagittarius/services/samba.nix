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
        "valid users" = [ "mw" "@nas" ];
      };
    };
  };
}
