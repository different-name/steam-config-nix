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

  fileSubmodule = types.submodule (
    { name, ... }:
    {
      options = {
        enable = lib.mkOption {
          type = types.bool;
          default = true;
          description = ''
            Whether to manage this file.

            When false the file is ignored, and any file previously placed for it is reverted.
          '';
        };

        source = lib.mkOption {
          type = types.nullOr types.path;
          default = null;
          example = lib.literalExpression "./mods/plugin.dll";
          description = ''
            File or directory to place. A directory is copied recursively and merged with whatever is already at the target.

            Exactly one of `source` or `text` must be set.
          '';
        };

        text = lib.mkOption {
          type = types.nullOr types.lines;
          default = null;
          description = ''
            Inline contents to place as a file.

            Exactly one of `source` or `text` must be set.
          '';
        };

        target = lib.mkOption {
          type = types.str;
          default = name;
          defaultText = lib.literalExpression "<name>";
          example = "BepInEx/plugins/plugin.dll";
          description = "Path relative to the root, defaulting to the attribute name.";
        };

        overwriteChanges = lib.mkOption {
          type = types.bool;
          default = true;
          example = false;
          description = ''
            Whether to re-apply this file on every activation.

            When true the declared contents are enforced each activation. When false the file is written once and then left alone, so changes the game or you make to it are preserved. Delete the file to re-apply.
          '';
        };

        executable = lib.mkOption {
          type = types.nullOr types.bool;
          default = null;
          example = true;
          description = ''
            Whether the placed file is executable.

            When null the executable bit is inherited from the source.
          '';
        };
      };
    }
  );

  resolveSource =
    entry: if entry.source != null then entry.source else pkgs.writeText "steam-config-nix-file" entry.text;

  mkFileOps =
    location: attrs:
    lib.mapAttrsToList (_: entry: {
      inherit location;
      inherit (entry) target overwriteChanges executable;
      source = "${resolveSource entry}";
    }) (lib.filterAttrs (_: entry: entry.enable) attrs);

  mkRemoveOps = location: paths: map (target: { inherit location target; }) paths;
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

    files.install = lib.mkOption {
      type = types.attrsOf fileSubmodule;
      default = { };
      example = lib.literalExpression ''
        {
          "BepInEx/plugins/plugin.dll".source = ./plugin.dll;
          "mod.cfg" = {
            source = ./mod.cfg;
            overwriteChanges = false;
          };
        }
      '';
      description = ''
        Files to place in the game's install directory, keyed by path relative to it. The app must be installed for these to be applied.
      '';
    };

    files.prefix = lib.mkOption {
      type = types.attrsOf fileSubmodule;
      default = { };
      example = lib.literalExpression ''
        {
          "drive_c/users/steamuser/AppData/Local/game/mod.xml".source = ./mod.xml;
        }
      '';
      description = ''
        Files to place in the app's Proton prefix, keyed by path relative to the prefix root (`compatdata/<id>/pfx`). The app must have been launched once for the prefix to exist.
      '';
    };

    removeFiles.install = lib.mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "movies/intro.bik" ];
      description = ''
        Paths in the game's install directory to remove, relative to it. A directory is removed recursively. Removed files are restored when the entry is unset.
      '';
    };

    removeFiles.prefix = lib.mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Paths in the app's Proton prefix to remove, relative to the prefix root.
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
    files = mkFileOps "install" config.files.install ++ mkFileOps "prefix" config.files.prefix;
    removeFiles =
      mkRemoveOps "install" config.removeFiles.install
      ++ mkRemoveOps "prefix" config.removeFiles.prefix;
  };
}
