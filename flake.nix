{
  description = "Declaratively manage Steam and your apps on NixOS or Home Manager";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    systems.url = "github:nix-systems/default";
  };

  outputs =
    inputs:
    let
      inherit (inputs) self;
      mkSteamConfigNixModule = import ./modules self;
    in
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;

      imports = [ ./checks ];

      perSystem =
        { self', pkgs, ... }:
        {
          packages = {
            default = self'.packages.steam-config-patcher;
            steam-config-patcher = pkgs.python3Packages.callPackage ./pkgs/steam-config-patcher/package.nix { };
            docs = pkgs.callPackage (import ./pkgs/docs/package.nix self) { };
          };

          formatter = pkgs.nixfmt;
        };

      flake = {
        nixosModules = {
          default = self.nixosModules.steam-config-nix;
          steam-config-nix = mkSteamConfigNixModule "nixos";
        };

        homeModules = {
          default = self.homeModules.steam-config-nix;
          steam-config-nix = mkSteamConfigNixModule "home-manager";
        };
      };
    };
}
