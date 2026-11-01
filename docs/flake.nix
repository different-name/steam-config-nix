{
  description = "Builds the documentation site";

  inputs = {
    steam-config-nix.url = ../.;

    # kept in this flake so it does not put a second nixpkgs and its own
    # transitive inputs into every downstream consumer of the root flake
    nuschtos-search = {
      url = "github:NuschtOS/search";
      inputs.nixpkgs.follows = "steam-config-nix/nixpkgs";
    };

    hextra = {
      url = "github:imfing/hextra/v0.12.3";
      flake = false;
    };
  };

  outputs =
    {
      steam-config-nix,
      nuschtos-search,
      hextra,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = steam-config-nix.inputs.nixpkgs.legacyPackages.${system};
    in
    {
      packages.${system}.default = pkgs.callPackage ./package.nix {
        inherit hextra;
        inherit (nuschtos-search.packages.${system}) mkSearch;
        inherit (steam-config-nix) homeModules;
      };
    };
}
