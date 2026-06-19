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

  artworkSubmodule = {
    options = {
      cover = lib.mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Vertical cover image (portrait, 600x900). Displayed in library grid view.";
        example = lib.literalExpression "./cover.jpg";
      };

      banner = lib.mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Horizontal banner image (460x215). Displayed on hover and in last played slot.";
        example = lib.literalExpression "./banner.jpg";
      };

      hero = lib.mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Hero/background image (1920x620). Displayed at the top of the game page.";
        example = lib.literalExpression "./hero.jpg";
      };

      logo = lib.mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Logo image (PNG with transparency). Displayed over the hero image.";
        example = lib.literalExpression "./logo.png";
      };
    };
  };
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
      description = "Image file to use as icon (shown in taskbar/tray).";
      example = lib.literalExpression "./icon.png";
    };

    artwork = lib.mkOption {
      type = types.submodule artworkSubmodule;
      default = { };
      description = ''
        Steam library artwork for this app.

        Steam uses a separate ID (based on CRC32 of the executable path and app name)
        to look up grid artwork files, which is different from the shortcut app ID.
        The patcher computes this automatically from `target` and `name`.
      '';
      example = lib.literalExpression ''
        {
          cover  = ./cover.jpg;   # 600x900
          banner = ./banner.jpg;  # 460x215
          hero   = ./hero.jpg;    # 1920x620
          logo   = ./logo.png;    # transparent PNG
        }
      '';
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
    artwork = {
      inherit (config.artwork)
        cover
        banner
        hero
        logo
        ;
    };
  };
}
