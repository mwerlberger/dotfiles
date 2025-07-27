{ pkgs
, username
, ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./apps.nix
    ./services/default.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.zfs.extraPools = [ "lake" ];

  # Power Management
  powerManagement.cpuFreqGovernor = "ondemand"; # or "powersave"

  networking.hostId = "5A6AE005"; # Must be set to a unique 8-char hex string for ZFS
  networking.hostName = "sagittarius"; # Define your hostname.

  # /etc/nixos/configuration.nix
  networking.interfaces.enp5s0 = {
    ipv6.addresses = [
      {
        address = "2a02:168:ff46::10";
        prefixLength = 64;
      }
    ];
  };

  # Set your time zone.
  time.timeZone = "Europe/Zurich";

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

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

  networking.firewall.allowedTCPPorts = [
    3000 # Grafana
    9090 # Prometheus
    445
    139 # Samba
  ];
  networking.firewall.allowedUDPPorts = [
    137
    138 # Samba
  ];

  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "25.05"; # Did you read the comment?
}
