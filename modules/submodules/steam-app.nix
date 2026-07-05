{
  lib,
  pkgs,
  dataDir,
}:
{ config, steamConfig, ... }:
let
  inherit (lib) types;
  baseAppModule = import ./base-app.nix { inherit lib pkgs dataDir; };
  libraryIconName = "steam-config-nix-${toString config.id}";
in
{
  imports = [ baseAppModule ];

  options = {
    id = lib.mkOption {
      type = types.int;
      example = 438100;
      description = "The Steam App ID. App IDs can be found through the game's store page URL.";
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

    language = lib.mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "german";
      description = ''
        Language to use for this app, as a Steam API language name (e.g. `"english"`, `"german"`, `"schinese"`).

        The app must be installed for this to be applied, Steam will download the language's depots on its next start.

        When unset again, Steam reverts to its default language for the app.
      '';
    };

    updateBehavior = lib.mkOption {
      type = types.nullOr (types.enum [
        "always"
        "onLaunch"
        "highPriority"
      ]);
      default = null;
      example = "onLaunch";
      description = ''
        How Steam keeps this app updated:

        - `"always"`: always keep the app updated
        - `"onLaunch"`: only update the app when it is launched
        - `"highPriority"`: always update this app before others

        The app must be installed for this to be applied. When unset again,
        Steam's default update behaviour is restored.
      '';
    };

    desktopEntry.useLibraryIcon = lib.mkOption {
      type = types.bool;
      default = steamConfig.desktopEntries.libraryIcons;
      defaultText = lib.literalExpression "config.programs.steam.config.desktopEntries.libraryIcons";
      example = false;
      description = ''
        Use the app's own icon from your Steam library for its desktop entry,
        instead of the generic Steam icon.

        Defaults to the global `programs.steam.config.desktopEntries.libraryIcons`
        option. Setting `desktopEntry.icon` explicitly always takes precedence.

        Has no effect unless `desktopEntry.enable` is set.
      '';
    };

    # only exists so setting it on a Steam app gives a helpful assertion
    # instead of "option does not exist"; real icons are non-Steam only
    artwork.icon = lib.mkOption {
      type = types.nullOr types.path;
      default = null;
      visible = false;
      internal = true;
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
  };
}
