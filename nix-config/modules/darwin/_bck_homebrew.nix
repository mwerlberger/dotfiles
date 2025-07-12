{ ... }: {
  nix-homebrew = {
    enable = true;
    enableRosetta = true;
    user = "mw";

    # Optional: Enable fully-declarative tap management
    mutableTaps = false;

    # Optional: Declarative tap management
    # taps = {
    #   "homebrew/homebrew-core" = homebrew-core;
    #   "homebrew/homebrew-cask" = homebrew-cask;
    #   "homebrew/homebrew-bundle" = homebrew-bundle;
    # };
  };
}
