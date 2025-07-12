{ inputs, pkgs, username, ... }:
{
  imports = [
    inputs.nix-homebrew.darwinModules.nix-homebrew
  ];

  nix-homebrew = {
    enable = true;

    # Apple Silicon Only: Also install Homebrew under the default Intel prefix for Rosetta 2
    enableRosetta = true;

    # User owning the Homebrew prefix
    user = username;

    # Optional: Declarative tap management
    # taps = {
    #   "homebrew/homebrew-core" = homebrew-core;
    #   "homebrew/homebrew-cask" = homebrew-cask;
    #   "homebrew/homebrew-bundle" = homebrew-bundle;
    # };

    # # Optional: Enable fully-declarative tap management
    # #
    # # With mutableTaps disabled, taps can no longer be added imperatively with `brew tap`.
    # mutableTaps = false;
  };

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