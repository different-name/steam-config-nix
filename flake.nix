{
  description = "Declarative Steam configuration for NixOS and Home Manager";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      mkModule = format: import ./modules { inherit self format; };
      # the checks' own inputs stay out of consumers' locks
      checkInputs = nixpkgs.lib.mapAttrs (_: node: builtins.fetchTree node.locked) (
        removeAttrs (nixpkgs.lib.importJSON ./checks/flake.lock).nodes [ "root" ]
      );
    in
    {
      nixosModules = {
        default = self.nixosModules.steam-config-nix;
        steam-config-nix = mkModule "nixos";
      };

      homeModules = {
        default = self.homeModules.steam-config-nix;
        steam-config-nix = mkModule "home-manager";
      };

      packages.${system} = {
        default = self.packages.${system}.steam-config-patcher;
        steam-config-launch = pkgs.callPackage ./pkgs/launch.nix { };
        steam-config-patcher = pkgs.callPackage ./pkgs/patcher.nix { };
      };

      checks.${system} = import ./checks {
        inherit
          self
          nixpkgs
          pkgs
          system
          ;
        inherit (checkInputs) home-manager;
      };

      formatter.${system} = pkgs.nixfmt-tree.override {
        runtimeInputs = [
          pkgs.rustfmt
          pkgs.prettier
        ];
        settings.formatter = {
          rustfmt = {
            command = "rustfmt";
            options = [
              "--edition"
              "2024"
            ];
            includes = [ "*.rs" ];
          };
          prettier = {
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
    };
}
