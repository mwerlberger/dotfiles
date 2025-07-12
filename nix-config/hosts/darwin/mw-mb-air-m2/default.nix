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
      cleanup = "uninstall";
      upgrade = true;
    };
    brewPrefix = "/opt/homebrew/bin";
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
      # "grid"
      # "google-chrome"
      # "handbrake"
      # "tailscale"
      # "bambu-studio"
      # "element"
      # "microsoft-outlook"
      # "monitorcontrol"
      "raycast"
      "mattermost"
      "freetube"
    ];
    brews = [
      "pulumi"
      "wget"
      "curl"
    ];
  };


}
