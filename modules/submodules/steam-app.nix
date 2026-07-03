{
  lib,
  pkgs,
  dataDir,
}:
{ name, config, ... }:
let
  inherit (lib) types;
  baseAppModule = import ./base-app.nix { inherit lib pkgs dataDir; };
in
{
  imports = [ baseAppModule ];

  options = {
    id = lib.mkOption {
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

    betaBranch = lib.mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "prerelease";
      description = ''
        Beta branch to opt this app into.

        The app must be installed for this to be applied, Steam will download the branch's build on its next start.

        When unset again, the app is reverted to the default branch.
      '';
    };
  };

  config.finalConfig = {
    inherit (config) betaBranch;
  };
}
