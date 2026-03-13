{
  lib,
  pkgs,
  dataDir,
}:
{ name, config, ... }:
let
  inherit (lib) types;
  baseAppModule = import ./base-app.nix { inherit lib pkgs dataDir; };

  appIdMin = lib.fromHexString "0x80000000";
  appIdMax = lib.fromHexString "0xFFFFFFFF";

  modulo = a: b: a - b * (a / b);

  seedToId =
    seed:
    let
      # fromHexString only supports a max value of 2^63, so this has to be trimmed
      hex = lib.substring 0 15 (builtins.hashString "md5" seed);
      base10 = lib.fromHexString hex;
      remainder = modulo base10 (appIdMax - appIdMin + 1);
    in
    remainder + appIdMin;
in
{
  imports = [ baseAppModule ];

  options = {
    seed = lib.mkOption {
      type = types.str;
      default = name;
      defaultText = lib.literalExpression "<name>";
      example = "vintage-story";
      description = ''
        The seed used to generate the app's ID.

        Seeds are used to generate apps IDs. And so shouldn't be changed once the app has been added.

        Changing an app ID for a Wine/Proton game will result in a new Wine prefix being created.
      '';
    };

    id = lib.mkOption {
      type = types.ints.between appIdMin appIdMax;
      default = seedToId config.seed;
      defaultText = lib.literalExpression "seedToId config.seed";
      example = 438100;
      description = ''
        The Steam App ID.

        App IDs can be found through the game's store page URL.

        If an ID is not provided, the app's `<name>` will be used.
      '';
    };

    name = lib.mkOption {
      type = types.singleLineStr;
      default = name;
      description = "Name to give this app.";
      example = "Vintage Story";
    };

    target = lib.mkOption {
      type = with types; coercedTo package lib.getExe path;
      description = "Executable for the app, either a package or absolute path.";
      example = lib.literalExpression "pkgs.vintagestory";
    };

    startIn = lib.mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Directory to start this app in.";
    };

    icon = lib.mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Image file to use as icon";
      example = lib.literalExpression "./icon.png";
    };

    isHidden = lib.mkOption {
      type = types.bool;
      default = false;
      description = "Whether this app should be hidden.";
      example = true;
    };

    allowOverlay = lib.mkOption {
      type = types.bool;
      default = true;
      description = "Whether this app should have the steam overlay.";
      example = false;
    };

    inVrLibrary = lib.mkOption {
      type = types.bool;
      default = false;
      description = "Whether this app is a VR app.";
      example = true;
    };
  };

  config.finalConfig = {
    inherit (config)
      name
      target
      startIn
      icon
      isHidden
      allowOverlay
      inVrLibrary
      ;
  };
}
