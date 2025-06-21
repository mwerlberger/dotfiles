# hosts/mw-mb-air-m2/default.nix
{ pkgs, ... }:

{
  # Import modules for this host.
  # You can create these files in the modules/ directory.
  imports = [
    ../../modules/darwin/default.nix
    ../../modules/shared/default.nix
  ];

  # Basic system info
  networking.hostName = "mw-mb-air-m2";
  system.stateVersion = 4; # Important!

  # User account for your Mac
  users.users.mw = {
    name = "mw";
    home = "/Users/mw";
  };
  system.primaryUser = "mw";

  # Homebrew configuration
  services.nix-homebrew = {
    enable = true;
    user = "mw";
    enableRosetta = true;
    # You can manage taps here if you want
    # taps = { ... };
  };

  # Other system-wide settings for this Mac
  system.defaults.scrollwheel.swipescrolldirection = false;
  system.keyboard.enableKeyMapping = true;

  # Location services, etc.
  locationd.enable = true;

  # Allow running apps from anywhere
  system.activationScripts.postActivation.text = "spctl --master-disable";
}