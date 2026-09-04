{
  description = "Declaratively manage Steam and your library on NixOS or Home Manager";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    systems.url = "github:nix-systems/x86_64-linux";

    # only the docs use this, so it should not put a second nixpkgs and its own
    # transitive inputs into every downstream consumer of this flake
    nuschtos-search = {
      url = "github:NuschtOS/search";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hextra = {
      url = "github:imfing/hextra/v0.12.3";
      flake = false;
    };
  };

  outputs =
    inputs:
    let
      inherit (inputs) self;
      inherit (inputs.nixpkgs) lib;
      mkSteamConfigNixModule =
        format:
        lib.modules.importApply ./modules {
          inherit self format;
        };
    in
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;

      imports = [ ./checks ];

      perSystem =
        {
          self',
          pkgs,
          inputs',
          ...
        }:
        {
          packages = {
            default = self'.packages.steam-config-patcher;
            steam-config-patcher = pkgs.python3Packages.callPackage ./pkgs/steam-config-patcher/package.nix { };
            docs = pkgs.callPackage (import ./pkgs/docs/package.nix self) {
              inherit (inputs'.nuschtos-search.packages) mkSearch;
            };
          };

          formatter = pkgs.nixfmt-tree.override {
            runtimeInputs = [
              pkgs.prettier
            ];
            settings.formatter.prettier = {
              command = "prettier";
              options = [
                "--write"
                "--prose-wrap"
                "always"
                "--print-width"
                "80"
              ];
              includes = [ "*.md" ];
            };
          };
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
