# hosts/nixos-vm/default.nix
{ pkgs
, username
, ... }:

{
  imports = [
    ./hardware-configuration.nix
    # ../../modules/nixos/default.nix
    # ../../modules/shared/default.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.zfs.extraPools = [ "lake" ];

  networking.hostId = "5A6AE005"; # Must be set to a unique 8-char hex string for ZFS
  networking.hostName = "sagittarius"; # Define your hostname.

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

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Enable sound.
  # services.pulseaudio.enable = true;
  # OR
  # services.pipewire = {
  #   enable = true;
  #   pulse.enable = true;
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

  # programs.firefox.enable = true;

  # List packages installed in system profile.
  # You can use https://search.nixos.org/ to find more packages (and options).
  environment.systemPackages = with pkgs; [
    gptfdisk
    smartmontools
    e2fsprogs
    fio
    lsof
    ethtool
    nettools
    ipmitool
    tmux
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
    curl
    #git
    #graphite-cli
    just
    fish
    bat
    eza
    yazi
    ripgrep
    jq
    yq-go
    fzf
    skim
    delta
  ];

  programs.git = {
    enable = true;
    config = {
      user.email = "code@werlberger.org";
      user.Name = "Manuel Werlberger";
      init.defaultBranch = "main";
      pull.rebase = true;
    };
  };

  programs.mosh.enable = true;
  programs.htop.enable = true;
  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
    defaultEditor = true;
  };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh = {
    enable = true;
    ports = [ 22 ];
    settings = {
      PasswordAuthentication = true;
      AllowUsers = null;
      UseDns = true;
      PermitRootLogin = "no";
    };
  };


  #  services.sanoid = {
  #    enable = true;
  #
  #    # Define policies for different datasets
  #    datasets = {
  #      # Snapshot policy for your data
  #      "lake" = {
  #        use_template = "default"; # Use the template defined below
  #        monthly = 12; # Keep 12 monthly snapshots
  #        daily = 30;   # Keep 30 daily snapshots
  #        hourly = 24;  # Keep 24 hourly snapshots
  #        frequently = 4; 
  #	recursive = true;
  #      };	
  #      # Override for lake/backups as those are mostly incremental (timemachine) backups.
  #      "lake/backups" = {
  #        use_template = "default"; # Use the template defined below
  #        monthly = 2;
  #        daily = 0;
  #        hourly = 0;
  #        frequently = 0;
  #	recursive = true;
  #      }
  #
  #      # A more conservative policy for your NixOS root pool
  #      "rpool/home" = {
  #        use_template = "default"; # Use the template defined below
  #        monthly = 12;
  #        daily = 14;
  #        hourly = 0;
  #        frequently = 0;
  #      }
  #      "rpool/var" = {
  #        use_template = "default"; # Use the template defined below
  #        monthly = 1;
  #        daily = 7;
  #        hourly = 0;
  #        frequently = 0;
  #      }
  #      "rpool/nix" = {
  #        use_template = "default"; # Use the template defined below
  #        monthly = 0;
  #        daily = 0;
  #        hourly = 0;
  #        frequently = 0;
  #	recursive = true;
  #      }
  #      "rpool/root" = {
  #        use_template = "default"; # Use the template defined below
  #        monthly = 2;
  #        daily = 7;
  #        hourly = 0;
  #        frequently = 0;
  #      }
  #    };
  #
  #    # Templates keep your config clean
  #    templates = {
  #      default = {
  #        autoprune = true; # Automatically delete snapshots that exceed retention limits
  #        recursive = false;
  #      };
  #    };
  #  };


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

  services = {
    # 1. Enable Prometheus and configure it to scrape metrics from node_exporter
    prometheus = {
      enable = true;
      scrapeConfigs = [
        {
          job_name = "node";
          static_configs = [{
            targets = [ "localhost:9100" ];
          }];
        }
      ];
    };

    # 2. Enable the node_exporter to collect system metrics
    prometheus.exporters.node = {
      enable = true;
      enabledCollectors = [ "systemd" "zfs" ]; # Add other collectors as needed
      # To monitor drive temperatures, you may need to enable the textfile collector
      # and use a script that outputs metrics in the Prometheus format.
    };

    # 3. Enable Grafana for visualization
    grafana = {
      enable = true;
      # If you are accessing it from other machines on your network
      settings.server = {
        http_addr = "0.0.0.0";
      };
    };
  };

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


  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "25.05"; # Did you read the comment?
}
