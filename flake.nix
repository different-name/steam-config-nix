{
  description = "Manage Steam launch options and other local config declaratively through Home Manager";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default";
  };

  outputs =
    inputs:
    let
      inherit (inputs.nixpkgs) lib;
      eachSystem = lib.genAttrs (import inputs.systems);
    in
    {
      packages = eachSystem (
        system:
        let
          pkgs = inputs.nixpkgs.legacyPackages.${system};
        in
        {
          steam-config-patcher = pkgs.python3Packages.callPackage ./pkgs/steam-config-patcher/package.nix { };
        }
      );

      homeModules.default =
        {
          config,
          lib,
          pkgs,
          ...
        }@args:
        import ./modules/steam-config.nix (args // { inherit inputs; });
    };
}
