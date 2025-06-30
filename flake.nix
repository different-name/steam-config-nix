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
          steamlcPackages = lib.packagesFromDirectoryRecursive {
            callPackage = lib.callPackageWith (pkgs // steamlcPackages // pkgs.python3 // pkgs.python3Packages);
            directory = ./pkgs;
          };
        in
        steamlcPackages
      );

      homeModules.default =
        {
          config,
          lib,
          pkgs,
          ...
        }@args:
        import ./modules/steam-localconfig.nix (args // { inherit inputs; });
    };
}
