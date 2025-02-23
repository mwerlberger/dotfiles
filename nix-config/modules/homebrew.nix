{nix-homebrew, ...}: {
  nix-homebrew.darwinModules.nix-homebrew
  {
    nix-homebrew = {
      enable = true;
      enableRosetta = true;
      user = "mw";

      # # Optional: Declarative tap management
      # taps = {
      #   "homebrew/homebrew-core" = homebrew-core;
      #   "homebrew/homebrew-cask" = homebrew-cask;
      #   "homebrew/homebrew-bundle" = homebrew-bundle;
      # };

      # Optional: Enable fully-declarative tap management
      #
      # With mutableTaps disabled, taps can no longer be added imperatively with `brew tap`.
      mutableTaps = false;
    };
  }

}
