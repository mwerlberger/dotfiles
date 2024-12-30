{
  pkgs,
  username,
  hostname,
  ...
} @ args:
#############################################################
#
#  Host & Users configuration
#
#############################################################
{
  networking.hostName = hostname;
  networking.computerName = hostname;
  system.defaults.smb.NetBIOSName = hostname;

  users.knownUsers = [ "${username}" ];
  users.users."${username}" = {
    home = "/Users/${username}";
    uid = 501;
    description = username;
    shell = pkgs.fish;
  };

  nix.settings.trusted-users = [username];
}
