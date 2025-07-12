{
  inputs,
  pkgs,
  username,
  ...
}:
{
  networking.hostName = "mw-mb-air-m2";
  networking.computerName = "mw-mb-air-m2";
  system.defaults.smb.NetBIOSName = "mw-mb-air-m2";
  

  # User account for your Mac
  users.users."${username}" = {
    name = "${username}";
    home = "/Users/${username}";
    uid = 501;
    # shell = pkgs.fish;
  };

  # Align nix-darwin's expected GID with the actual system GID.
  ids.gids.nixbld = 350;

  imports = [
    ./system.nix
    ./apps.nix
    # ./homebrew.nix
    #   "${inputs.secrets}/work.nix"
    #   ./secrets.nix
  ];


  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      cleanup = "zap"; # was uninstall
      upgrade = true;
    };

    brewPrefix = "/opt/homebrew/bin";
    taps = [
      # "homebrew/services"
    ];
    caskArgs = {
      no_quarantine = true;
    };
    casks = [
      {
        name = "ghostty";
        greedy = true;
      }
      {
        name = "vivaldi";
        greedy = true;
      }
      # "notion"
      "telegram"
      # "libreoffice"
      "signal"
      "grid"
      # "google-chrome"
      # "handbrake"
      # "tailscale"
      # "bambu-studio"
      # "element"
      # "microsoft-outlook"
      # "monitorcontrol"
      # "raycast"
      "freetube"
    ];
    brews = [
      "pulumi"
      "wget"
      "curl"
    ];


       # Applications to install from Mac App Store using mas.
    # You need to install all these Apps manually first so that your apple account have records for them.
    # otherwise Apple Store will refuse to install them.
    # For details, see https://github.com/mas-cli/mas
    masApps = {
      PaprikaRecipeManager3 = 1303222628;
      # Xcode = 497799835;
      # Wechat = 836500024;
      # NeteaseCloudMusic = 944848654;
      # QQ = 451108668;
      # WeCom = 1189898970;  # Wechat for Work
      # TecentMetting = 1484048379;
      # QQMusic = 595615424;
    };


  };


}
