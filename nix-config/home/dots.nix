{ ... }:
let
  home = {
    username = "mw";
    homeDirectory = "/home/mw";
    stateVersion = "25.05";
  };
in
{

  nixpkgs = {
    overlays = [ ];
    config = {
      allowUnfree = true;
      allowUnfreePredicate = (_: true);
    };
  };

  home = home;

  # imports = [
  #   ../../dots/zsh/default.nix
  #   ../../dots/nvim/default.nix
  #   ../../dots/neofetch/default.nix
  #   ./gitconfig.nix
  # ];

  programs.nix-index = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.home-manager.enable = true;

  # systemd.user.startServices = "sd-switch";
}
