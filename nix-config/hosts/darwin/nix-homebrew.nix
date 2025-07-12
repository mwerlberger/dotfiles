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
}
