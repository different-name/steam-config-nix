{
  description = "Manage Steam launch options and other local config declaratively through Home Manager";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    systems.url = "github:nix-systems/default";
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;

      perSystem =
        { self', pkgs, ... }:
        {
          packages = {
            default = self'.packages.steam-config-patcher;
            steam-config-patcher = pkgs.python3Packages.callPackage ./pkgs/steam-config-patcher/package.nix { };
          };
        };

      flake.homeModules = {
        default = inputs.self.homeModules.steam-config-nix;
        steam-config-nix = import ./modules/steam-config.nix inputs.self;
      };
    };
}
