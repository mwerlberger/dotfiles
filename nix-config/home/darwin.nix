{ inputs, pkgs, ... }: {
  nixpkgs.overlays = [
    inputs.nix-darwin-browsers.overlays.default
  ];

  home.packages = [
    pkgs.zen-browser-bin
  ];
}
