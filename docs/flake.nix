{
  description = "Private inputs for documentation, used by the `docs` partition";

  inputs = {
    steam-config-nix.url = ../.;

    # only the docs use this, so it should not put a second nixpkgs and its own
    # transitive inputs into every downstream consumer of this flake
    nuschtos-search = {
      url = "github:NuschtOS/search";
      inputs.nixpkgs.follows = "steam-config-nix/nixpkgs";
    };

    hextra = {
      url = "github:imfing/hextra/v0.12.3";
      flake = false;
    };
  };

  outputs = _: { };
}
