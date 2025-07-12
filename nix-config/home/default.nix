{ username, ... }:
let
  home = {
    username = "${username}";
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
  

  imports = [
    ./git.nix
    ./apps.nix
  #   ../../dots/zsh/default.nix
  #   ../../dots/nvim/default.nix
  #   ../../dots/neofetch/default.nix
  #   ./gitconfig.nix
  ];

  programs.home-manager.enable = true;
  # systemd.user.startServices = "sd-switch";
}
