# { inputs }:

# import ./mkSystem.nix { inherit inputs; }


inputs:
let
  hostsDir = ../hosts;
  homeManagerCfg = userPackages: extraImports: {
    home-manager.useGlobalPkgs = false;
    home-manager.extraSpecialArgs = {
      inherit inputs;
    };
    home-manager.users.mw.imports = [
      # inputs.agenix.homeManagerModules.default
      inputs.nix-index-database.hmModules.nix-index
      ../home
      # ./users/mw/age.nix
    ] ++ extraImports;
    home-manager.backupFileExtension = "bak";
    home-manager.useUserPackages = userPackages;
  };
in
{
  mkDarwin = machineHostname: nixpkgsVersion: extraHmModules: extraModules: {
    darwinConfigurations.${machineHostname} = inputs.nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      specialArgs = {
        inherit inputs;
        username = "mw";
      };
      modules = [
        # inputs.agenix-darwin.darwinModules.default
        ../hosts/darwin/nix-homebrew.nix
        ../hosts/darwin
        ../hosts/darwin/${machineHostname}
        inputs.home-manager-unstable.darwinModules.home-manager
        (nixpkgsVersion.lib.attrsets.recursiveUpdate (homeManagerCfg true extraHmModules) {
          home-manager.users.mw.home.homeDirectory = nixpkgsVersion.lib.mkForce "/Users/mw";
          home-manager.extraSpecialArgs = {
            username = "mw";
          };
        })
      ] ++ extraModules;
    };
  };
  
  mkNixos = machineHostname: nixpkgsVersion: extraModules: rec {
    deploy.nodes.${machineHostname} = {
      hostname = machineHostname;
      profiles.system = {
        user = "root";
        sshUser = "mw";
        path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos nixosConfigurations.${machineHostname};
      };
    };
    nixosConfigurations.${machineHostname} = nixpkgsVersion.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
      };
      modules = [
        # ./homelab
        # ./machines/nixos/_common
        # ./machines/nixos/${machineHostname}
        # ./modules/email
        # ./modules/tg-notify
        # ./modules/auto-aspm
        # ./modules/mover
        # inputs.agenix.nixosModules.default
        # ./users/mw
        (homeManagerCfg false [ ])
      ] ++ extraModules;
    };
  };
  
  mkMerge = inputs.nixpkgs-stable.lib.lists.foldl' (
    a: b: inputs.nixpkgs-stable.lib.attrsets.recursiveUpdate a b
  ) { };
}
