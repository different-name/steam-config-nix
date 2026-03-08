{
  lib,
  pkgs,
  dataDir,
}:
{ name, ... }:
let
  inherit (lib) types;
  baseAppModule = import ./base-app.nix { inherit lib pkgs dataDir; };
in
{
  imports = [ baseAppModule ];

  options.id = lib.mkOption {
    type = types.int;
    default = lib.strings.toIntBase10 name;
    defaultText = lib.literalExpression "lib.strings.toIntBase10 <name>";
    example = 438100;
    description = ''
      The Steam App ID.

      App IDs can be found through the game's store page URL.

      If an ID is not provided, the app's `<name>` will be used.
    '';
  };
}
