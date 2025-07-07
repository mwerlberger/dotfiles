{ inputs }:

let
  # Your personal details, kept in one place
  username = "mw";
  useremail = "manuel@werlberger.org";
  hostsDir = ../hosts;
in
{
  # == NIXOS SYSTEM FACTORY ==
  mkNixosSystem = { hostname, system ? "x86_64-linux", pkgs, home-manager }:
    inputs.nixpkgs-stable.lib.nixosSystem {
      inherit system;
      specialArgs = inputs // { inherit username useremail; }; # Pass inputs and user details to modules

      modules = [
        # 1. Host-specific configuration (networking, hardware, etc.)
        "${hostsDir}/${hostname}"

        # 2. Home Manager configuration
        home-manager.nixosModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            extraSpecialArgs = inputs // { inherit username useremail; };
            # Import the user's home-manager config from their host folder
            users.${username} = import "${hostsDir}/${hostname}/home.nix";
          };
        }
      ];
    };

  # == Darwin system factory ==
  mkDarwin = hostname: nixpkgsVersion: extraHmModules: extraModules: {
    darwinConfigurations.${hostname} = inputs.nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      specialArgs = {
        inherit inputs;
      };
      modules = [
        # inputs.agenix-darwin.darwinModules.default
        ${hostsDir}
        ${hostsDir}/${hostname}
        # inputs.home-manager-unstable.darwinModules.home-manager
        # (nixpkgsVersion.lib.attrsets.recursiveUpdate (homeManagerCfg true extraHmModules) {
        #   home-manager.users.notthebee.home.homeDirectory = nixpkgsVersion.lib.mkForce "/Users/notthebee";
        # })
      ] ++ extraModules;
    };
  };

  # == DARWIN SYSTEM FACTORY ==
  mkDarwinSystem = { hostname, system ? "aarch64-darwin", pkgs, home-manager }:
    inputs.nix-darwin.lib.darwinSystem {
      inherit system;
      specialArgs = inputs // { inherit username useremail; };

      modules = [
        # 1. Host-specific configuration
        "${hostsDir}/${hostname}"

        # # 2. Home Manager configuration
        # home-manager.darwinModules.home-manager
        # {
        #   home-manager = {
        #     useGlobalPkgs = true;
        #     useUserPackages = true;
        #     extraSpecialArgs = inputs // { inherit username useremail; };
        #     users.${username} = import "${hostsDir}/${hostname}/home";
        #   };
        # }
      ];
    };
}