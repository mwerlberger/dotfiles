{
  description = "MW's Nix Configuration";

  nixConfig = {
    allowUnfree = true;
    experimental-features = [ "nix-command" "flakes" ];
    # # Optionally, keep your cross-platform/cachix settings:
    # extra-platforms = [ "x86_64-linux" ];
    # extra-substituters = [
    #   "https://nix-community.cachix.org"
    # ];
    # extra-trusted-public-keys = [
    #   "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    # ];
  };

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";

    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    home-manager-stable = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };
    home-manager-unstable = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    nix-index-database = {
      url = "github:Mic92/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };
    deploy-rs.url = "github:serokell/deploy-rs";

  # Secrets management (encrypted with age/SSH keys)
  agenix.url = "github:ryantm/agenix";

    # Homebrew including declarative tap management
    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
    homebrew-bundle = {
      url = "github:homebrew/homebrew-bundle";
      flake = false;
    };
  };

  outputs =
    inputs @ { self
    , ...
    }:
    let
      # Import our library of helper functions
      lib = import ./lib inputs;
      # inherit (lib) mkMerge mkDarwin;
      # lib = import ./lib { inherit inputs; };
      # formatter = inputs.flake-utils.lib.eachDefaultSystem (system:
      #   inputs.nixpkgs.legacyPackages.${system}.alejandra
      # );
    in
    lib.mkMerge [
      (lib.mkDarwin
        "mw-mb-air-m2"
        inputs.nixpkgs-darwin
        [ ]
        [ ]
      )
      (lib.mkNixos
        "sagittarius"
        inputs.nixpkgs-stable
  [ ]
  [ ./modules/tailscale.nix ]
      )
    ];
}
