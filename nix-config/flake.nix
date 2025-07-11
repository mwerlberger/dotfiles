{
  description = "MW's Nix Configuration";

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
        [

        ]
      )
    ];
  # {
  #   # == Your NixOS Machine(s) ==
  #   nixosConfigurations."sagittarius" = lib.mkNixosSystem {
  #     hostname = "sagittarius";
  #     # Pinning to stable channels
  #     pkgs = inputs.nixpkgs;
  #     home-manager = inputs.home-manager-stable;
  #   };

  #   # == Your Darwin Machine(s) ==
  #   darwinConfigurations."mw-mb-air-m2" = lib.mkDarwinSystem {
  #     hostname = "mw-mb-air-m2";
  #     # Using unstable channels for newer packages on the Mac
  #     pkgs = inputs.nixpkgs-darwin;
  #     home-manager = inputs.home-manager-unstable;
  #   };
  # }


  #   darwinConfigurations."${hostname}" = inputs.darwin.lib.darwinSystem {
  #     inherit system specialArgs;
  #     modules = [
  #       # homebrew
  #       inputs.nix-homebrew.darwinModules.nix-homebrew
  #       {
  #         nix-homebrew = {
  #           # Install Homebrew under the default prefix
  #           enable = true;

  #           # Apple Silicon Only: Also install Homebrew under the default Intel prefix for Rosetta 2
  #           enableRosetta = true;

  #           # User owning the Homebrew prefix
  #           user = "mw";

  #           # Optional: Declarative tap management
  #           # taps = {
  #           #   "homebrew/homebrew-core" = homebrew-core;
  #           #   "homebrew/homebrew-cask" = homebrew-cask;
  #           #   "homebrew/homebrew-bundle" = homebrew-bundle;
  #           # };

  #           # # Optional: Enable fully-declarative tap management
  #           # #
  #           # # With mutableTaps disabled, taps can no longer be added imperatively with `brew tap`.
  #           # mutableTaps = false;
  #         };
  #       }

  #       # Import other nix-darwin module configs
  #       ./modules/nix-core.nix
  #       ./modules/system.nix
  #       # ./modules/homebrew.nix
  #       ./modules/apps.nix
  #       ./modules/fish.nix
  #       # ./modules/homebrew-mirror.nix # comment this line if you don't need a homebrew mirror
  #       ./modules/host-users.nix

  #       # home manager
  #       inputs.home-manager-unstable.darwinModules.home-manager
  #       {
  #         home-manager.useGlobalPkgs = true;
  #         home-manager.useUserPackages = true;
  #         home-manager.extraSpecialArgs = specialArgs;
  #         home-manager.users.${username} = import ./home;
  #       }
  #     ];
  #   };

  #   # nix code formatter
  #   formatter.${system} = inputs.nixpkgs-unstable.legacyPackages.${system}.alejandra;
  # };
}
