{
  lib,
  pkgs,
  nixosOptionsDoc,
  homeModules,
}:
let
  eval = lib.evalModules {
    specialArgs = { inherit pkgs; };
    modules = [
      { config._module.check = false; }
      homeModules.default
    ];
  };
in
(nixosOptionsDoc { inherit (eval) options; }).optionsJSON + "/share/doc/nixos/options.json"
