{
  description = "MW's nix for macOS configuration";

  ##################################################################################################################
  #
  # Want to know Nix in details? Looking for a beginner-friendly tutorial?
  # Check out https://github.com/ryan4yin/nixos-and-flakes-book !
  #
  ##################################################################################################################

  # the nixConfig here only affects the flake itself, not the system configuration!
  # nixConfig =
  #   substituters = [
  #     # Query the mirror of USTC first, and then the official cache.
  #     # "https://mirrors.ustc.edu.cn/nix-channels/store"
  #     "https://cache.nixos.org"
  #   ];
  # };

  # This is the standard format for flake.nix. `inputs` are the dependencies of the flake,
  # Each item in `inputs` will be passed as a parameter to the `outputs` function after being pulled and built.
  inputs = {
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    # nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-24.11-darwin";

    darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };

    # home-manager, used for managing user configuration
    home-manager = {
      # url = "github:nix-community/home-manager/release-24.11";
      url = "github:nix-community/home-manager/master";
      # The `follows` keyword in inputs is used for inheritance.
      # Here, `inputs.nixpkgs` of home-manager is kept consistent with the `inputs.nixpkgs` of the current flake,
      # to avoid problems caused by different versions of nixpkgs dependencies.
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };

    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";
    # Optional: Declarative tap management
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

  # The `outputs` function will return all the build results of the flake.
  # A flake can have many use cases and different types of outputs,
  # parameters in `outputs` are defined in `inputs` and can be referenced by their names.
  # However, `self` is an exception, this special parameter points to the `outputs` itself (self-reference)
  # The `@` syntax here is used to alias the attribute set of the inputs's parameter, making it convenient to use inside the function.
  outputs = inputs @ {
    self,
    nixpkgs,
    darwin,
    home-manager,
    nix-homebrew,
    homebrew-core,
    homebrew-cask,
    homebrew-bundle,
    ...
  }: let
    username = "mw";
    useremail = "manuel@werlberger.org";
    system = "aarch64-darwin";
    hostname = "mw-mb-air-m2";

    specialArgs =
      inputs
      // {
        inherit username useremail hostname;
      };
  in {
    darwinConfigurations."${hostname}" = darwin.lib.darwinSystem {
      inherit system specialArgs;
      modules = [
        # homebrew
        nix-homebrew.darwinModules.nix-homebrew
        {
          nix-homebrew = {
            # Install Homebrew under the default prefix
            enable = true;

            # Apple Silicon Only: Also install Homebrew under the default Intel prefix for Rosetta 2
            enableRosetta = true;

            # User owning the Homebrew prefix
            user = "mw";

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

        # Import other nix-darwin module configs
        ./modules/nix-core.nix
        ./modules/system.nix
        # ./modules/homebrew.nix
        ./modules/apps.nix
        ./modules/fish.nix
        # ./modules/homebrew-mirror.nix # comment this line if you don't need a homebrew mirror
        ./modules/host-users.nix

        # home manager
        home-manager.darwinModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = specialArgs;
          home-manager.users.${username} = import ./home;
        }
      ];
    };

    # nix code formatter
    formatter.${system} = nixpkgs.legacyPackages.${system}.alejandra;
  };
}
