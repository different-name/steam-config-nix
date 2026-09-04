{
  lib,
  pkgs,
  dataDir,
}:
{
  config,
  name,
  steamConfig,
  ...
}:
let
  inherit (lib) types;
  baseAppModule = lib.modules.importApply ./base-app.nix { inherit lib pkgs dataDir; };
  steamAppFilesModule = lib.modules.importApply ./steam-app-files.nix { inherit lib pkgs; };
  keyIsId = lib.match "[0-9]+" name != null;
  notKeyedById = ''steam-config-nix: apps."${name}" must be keyed by its Steam App ID, as apps."<id>" = { name = "${name}"; ... }'';
  libraryIconName = "steam-config-nix-${toString config.id}";
in
{
  imports = [
    baseAppModule
    steamAppFilesModule
  ];

  options = {
    id = lib.mkOption {
      type = types.int;
      default = if keyIsId then lib.toInt name else throw notKeyedById;
      defaultText = lib.literalMD "the attribute name";
      apply =
        v:
        if !keyIsId then
          throw notKeyedById
        else if v != lib.toInt name then
          throw ''steam-config-nix: apps."${name}" sets id ${toString v}, which disagrees with its key''
        else
          v;
      example = 438100;
      description = ''
        The Steam App ID, taken from the attribute name.
      '';
    };

    name = lib.mkOption {
      type = types.singleLineStr;
      default = toString config.id;
      defaultText = lib.literalExpression "toString config.id";
      example = "VRChat";
      description = ''
        Name for this app, used for its desktop entry, its systemd target, and the wrapper's own messages.

        Steam has its own name for the app, which this does not change.
      '';
    };

    betaBranch = lib.mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "prerelease";
      description = ''
        Beta branch to opt this app into.

        The app must be installed for this to be applied. Steam downloads the branch's build on its next start.

        When unset again, Steam's own default is restored.
      '';
    };

    language = lib.mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "german";
      description = ''
        Language to use for this app, as a Steam API language code (e.g. `"english"`, `"german"`, `"schinese"`). The full set is the API language code column of [Steam's supported languages](https://partner.steamgames.com/doc/store/localization/languages).

        The app must be installed for this to be applied. Steam downloads the language's depots on its next start.

        When unset again, Steam's own default is restored.
      '';
    };

    updateBehavior = lib.mkOption {
      type = types.nullOr (
        types.enum [
          "always"
          "onLaunch"
          "highPriority"
        ]
      );
      default = null;
      example = "onLaunch";
      description = ''
        How Steam keeps this app updated:

        - `"always"`: always keep the app updated
        - `"onLaunch"`: only update the app when it is launched
        - `"highPriority"`: always update this app before others

        The app must be installed for this to be applied. When unset again, Steam's own default is restored.
      '';
    };

    allowDownloadsWhileRunning = lib.mkOption {
      type = types.nullOr (
        types.enum [
          "followGlobal"
          "always"
          "never"
        ]
      );
      default = null;
      example = "always";
      description = ''
        Whether Steam may download other apps while this app is running:

        - `"followGlobal"`: use the global download setting
        - `"always"`: always allow downloads while this app runs
        - `"never"`: never allow downloads while this app runs

        The app must be installed for this to be applied. When unset again, Steam's own default is restored.
      '';
    };

    desktopEntry.useLibraryIcon = lib.mkOption {
      type = types.bool;
      default = steamConfig.desktopEntries.libraryIcons;
      defaultText = lib.literalExpression "config.programs.steam.config.desktopEntries.libraryIcons";
      example = false;
      description = ''
        Use the app's own icon from your Steam library for its desktop entry, instead of the generic Steam icon.

        Setting `desktopEntry.icon` explicitly always takes precedence.

        Has no effect unless `desktopEntry.enable` is set.
      '';
    };
  };

  config.desktopEntry.icon = lib.mkIf config.desktopEntry.useLibraryIcon (
    lib.mkDefault libraryIconName
  );

  config.finalConfig = {
    inherit (config) betaBranch language;
    libraryIcon = config.desktopEntry.enable && config.desktopEntry.icon == libraryIconName;
    updateBehavior =
      if config.updateBehavior == null then
        null
      else
        {
          always = "0";
          onLaunch = "1";
          highPriority = "2";
        }
        .${config.updateBehavior};
    allowDownloadsWhileRunning =
      if config.allowDownloadsWhileRunning == null then
        null
      else
        {
          followGlobal = "0";
          always = "1";
          never = "2";
        }
        .${config.allowDownloadsWhileRunning};
  };
}
