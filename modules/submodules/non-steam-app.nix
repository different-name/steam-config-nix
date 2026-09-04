{
  lib,
  pkgs,
  dataDir,
}:
{ name, config, ... }:
let
  inherit (lib) types;
  baseAppModule = lib.modules.importApply ./base-app.nix { inherit lib pkgs dataDir; };

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

  # appid << 32 | 0x02000000 exceeds nix's 2^63 int limit, so it is built as a decimal string
  mkShortcutGameId =
    appid:
    let
      shift = 4294967296;
      shortcutFlag = 33554432;
      hi = appid / 1000000;
      lo = appid - hi * 1000000;
      r = lo * shift + shortcutFlag;
      rHi = r / 1000000;
      rLo = r - rHi * 1000000;
      top = hi * shift + rHi;
    in
    "${toString top}${lib.fixedWidthString 6 "0" (toString rLo)}";
in
{
  imports = [ baseAppModule ];

  options = {
    seed = lib.mkOption {
      type = types.str;
      default = name;
      defaultText = lib.literalMD "the attribute name";
      example = "vintage-story";
      description = ''
        Seed used to generate the app's ID.

        Do not change this once the app has been added. The ID follows the seed, and a new ID means a new Wine prefix for a Proton app, and a fresh shortcut with no artwork or play time.
      '';
    };

    id = lib.mkOption {
      type = types.ints.between appIdMin appIdMax;
      default = seedToId config.seed;
      defaultText = lib.literalMD "an ID derived from the seed";
      example = 2496815253;
      description = ''
        Steam App ID for this app's shortcut.

        Set this only to match an ID Steam has already assigned. Normally it is derived from `seed`.
      '';
    };

    name = lib.mkOption {
      type = types.singleLineStr;
      default = name;
      defaultText = lib.literalMD "the attribute name";
      example = "Vintage Story";
      description = ''
        Name for this app, shown in the Steam library, and used for its desktop entry, its systemd target, and the wrapper's own messages.
      '';
    };

    target = lib.mkOption {
      type = with types; coercedTo package lib.getExe path;
      example = lib.literalExpression "pkgs.vintagestory";
      description = "Executable for the app, either a package or absolute path.";
    };

    startIn = lib.mkOption {
      type = types.nullOr types.path;
      default = dirOf config.target;
      defaultText = lib.literalExpression "dirOf config.target";
      example = "/home/alice/Games/some-game";
      description = "Directory to start this app in.";
    };

    isHidden = lib.mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = "Whether to hide this app in the Steam library.";
    };

    allowOverlay = lib.mkOption {
      type = types.bool;
      default = true;
      example = false;
      description = "Whether the Steam overlay is enabled for this app.";
    };

    inVrLibrary = lib.mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = "Whether to list this app in Steam's VR library.";
    };

    artwork.icon = lib.mkOption {
      type = types.nullOr types.path;
      default = null;
      example = lib.literalExpression "./icon.png";
      description = ''
        Icon shown in the taskbar and shortcut list, and the default for the app's desktop entry.
      '';
    };

  };

  config = {
    steamRunId = mkShortcutGameId config.id;

    desktopEntry.icon = lib.mkIf (config.artwork.icon != null) (lib.mkDefault config.artwork.icon);

    finalConfig = {
      inherit (config)
        name
        target
        startIn
        isHidden
        allowOverlay
        inVrLibrary
        ;
      icon = config.artwork.icon;
    };
  };
}
