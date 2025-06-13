{
  description = "Home Manager module for declarative Steam game launch options";

  inputs = {
    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    systems.url = "github:nix-systems/default-linux";
  };

  outputs = inputs:
    inputs.flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import inputs.nixpkgs {inherit system;};
      in {
        packages = import ./pkgs {inherit pkgs inputs;};
      }
    )
    // {
      homeModules.steam-launch = {
        config,
        lib,
        pkgs,
        ...
      } @ args:
        import ./modules/steam-launch.nix (args // {inherit inputs;});
    };
}
