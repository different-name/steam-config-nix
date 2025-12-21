self:
{
  lib,
  pkgs,
  stdenv,
  nixosOptionsDoc,
  ...
}:
let
  eval = lib.evalModules {
    specialArgs = { inherit pkgs; };
    modules = [
      { config._module.check = false; }
      self.homeModules.default
    ];
  };

  optionsDoc = nixosOptionsDoc {
    options = { inherit (eval.options) programs; };
  };
in
stdenv.mkDerivation {
  name = "steam-config-nix-docs";
  src = ./.;
  buildPhase = ''
    mkdir -p $out
    cat ${optionsDoc.optionsCommonMark} > $out/options.md
  '';
}
