{ ... }:
{
  nixpkgs.config.allowUnfree = true;
  # nixpkgs.config.allowUnfreePredicate = (_: true);

  # nixpkgs = {
  #   overlays = [
  #     (self: super: {
  #       nodejs = super.nodejs_22;
  #       karabiner-elements = super.karabiner-elements.overrideAttrs (old: {
  #         version = "14.13.0";

  #         src = super.fetchurl {
  #           inherit (old.src) url;
  #           hash = "sha256-gmJwoht/Tfm5qMecmq1N6PSAIfWOqsvuHU8VDJY8bLw=";
  #         };
  #       });
  #     })
  #   ];
  # };

  # services.karabiner-elements.enable = true;
  nix = {
    settings = {
      experimental-features = ["nix-command" "flakes"];
      max-jobs = "auto";
      trusted-users = [
        "root"
        "mw"
        "@admin"
      ];
    };
    gc = {
      automatic = true;
      options = "--delete-older-than 7d";
    };
    # package = pkgs.nix;
  };
}
