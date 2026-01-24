{ config
, pkgs
, username
, ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./hardware-graphics.nix
    ./agenix.nix
    ./network.nix
    ./vpn.nix
    ./apps.nix
    ./services/default.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.zfs.extraPools = [ "lake" ];

  # Power Management
  powerManagement.cpuFreqGovernor = "ondemand"; # or "powersave"

  # Set your time zone.
  time.timeZone = "Europe/Zurich";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";
  # console = {
  #   font = "Lat2-Terminus16";
  #   keyMap = "us";
  #   useXkbConfig = true; # use xkb.options in tty.
  # };

  security.sudo.wheelNeedsPassword = false;

  users.groups.nas = {
    gid = 1000;
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.mw = {
    uid = 1000;
    isNormalUser = true;
    extraGroups = [ "wheel" "users" "nas" ]; # Enable ‘sudo’ for the user.
    hashedPassword = "$y$j9T$mg90ljeF0GfEaJbNT81X1/$Tvkmsgs2Ogi.osNIN9qfNAmCxQlm8HplZL3tVLp/zjB";
  };

  # Make sure the data lake permissions are set correctly
  # Lets disable and see if we can do it purely with ZFS
  # systemd.services.set-data-lake-permissions = {
  #   description = "Set permissions for /data/lake ZFS dataset";
  #   after = [ "zfs-mount.service" ];
  #   wantedBy = [ "multi-user.target" ];
  #   serviceConfig = {
  #     Type = "oneshot";
  #     ExecStart = "${pkgs.coreutils}/bin/chown mw:nas /data/lake";
  #     ExecStartPost = "${pkgs.coreutils}/bin/chmod 0770 /data/lake";
  #   };
  # };


  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    download-buffer-size = 268435456; # 256 MB
  };

  nixpkgs.config.allowUnfree = true;

  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "25.05"; # Did you read the comment?
}
