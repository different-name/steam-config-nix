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

  placeSubmodule = types.submodule (
    { name, ... }:
    {
      imports = [
        # declares the `warnings` option the mode migration writes to
        "${pkgs.path}/nixos/modules/misc/assertions.nix"
        (lib.mkChangedOptionModule [ "overwriteChanges" ] [ "mode" ] (
          entry: if entry.overwriteChanges then "enforce" else "seed"
        ))
      ];

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

        mode = lib.mkOption {
          type = types.enum [
            "enforce"
            "seed"
            "lock"
          ];
          default = "enforce";
          example = "seed";
          description = ''
            How the file is managed across activations.

            - `"enforce"`: re-apply the declared contents every activation, overwriting drift.
            - `"seed"`: write once if absent, then leave it editable so your and the game's changes are kept. Delete it to re-apply.
            - `"lock"`: like `"enforce"`, but the placed file is made read-only so nothing else can change it.
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

  patchSubmodule = types.submodule (
    { name, ... }:
    {
      options = {
        enable = lib.mkOption {
          type = types.bool;
          default = true;
          description = ''
            Whether to apply this patch.

            When false the patch is ignored, and the target file is reverted to its pre-patch contents.
          '';
        };

        target = lib.mkOption {
          type = types.str;
          default = name;
          defaultText = lib.literalExpression "<name>";
          example = "Engine/Config/BaseEngine.ini";
          description = "Path relative to the root, defaulting to the attribute name.";
        };

        format = lib.mkOption {
          type = types.enum [
            "ini"
            "json"
            "registry"
            "keyvalue"
            "unityPrefs"
            "sourceConvars"
          ];
          example = "ini";
          description = ''
            Format of the target file, so the patcher can read, merge, and write it back.

            - `"ini"`: `content` is an attrset of section names to attrsets of key/value pairs.
            - `"json"`: `content` is a nested attrset deep-merged into the file.
            - `"registry"`: a Wine registry file (`system.reg`/`user.reg`). `content` maps a key path to an attrset of value names, where a string becomes a `REG_SZ` and an integer a `REG_DWORD`. The path separator may be `/` or `\\`.
            - `"keyvalue"`: a Valve KeyValues (VDF) file. `content` is a nested attrset deep-merged into the file.
            - `"unityPrefs"`: Unity PlayerPrefs in a Wine `user.reg`. `content` maps a registry path (`Software/<Company>/<Product>`, using `/` or `\\` as the separator) to an attrset of PlayerPrefs keys, hashing each key the way Unity does and encoding the value by its type (integer, float, boolean, or string).
            - `"sourceConvars"`: a Source engine console config (GoldSrc, Source, or Source 2, such as an `autoexec.cfg`). `content` is a flat attrset of console variable to value. Each named variable is set in place, or appended if absent, and everything else in the file (binds, aliases, comments) is left untouched. A boolean is written as `1`/`0`.
          '';
        };

        content = lib.mkOption {
          type = types.attrs;
          example = lib.literalExpression "{ Display.Fullscreen = 1; }";
          description = ''
            Keys to set in the target file, shaped per `format`. Keys already in the file that are not listed here are left untouched.
          '';
        };

        createIfMissing = lib.mkOption {
          type = types.bool;
          default = false;
          example = true;
          description = ''
            Create the target file containing just these keys when it does not exist yet.

            When off, the patch waits for the game to generate the file, retrying on each activation until it appears.
          '';
        };
      };
    }
  );

  resolveSource =
    entry:
    if entry.source != null then entry.source else pkgs.writeText "steam-config-nix-file" entry.text;

  mkFileOps =
    location: attrs:
    lib.mapAttrsToList (_: entry: {
      inherit location;
      inherit (entry) target mode executable;
      source = "${resolveSource entry}";
    }) (lib.filterAttrs (_: entry: entry.enable) attrs);

  mkRemoveOps = location: paths: map (target: { inherit location target; }) paths;

  mkPatchOps =
    location: attrs:
    lib.mapAttrsToList (_: entry: {
      inherit location;
      inherit (entry)
        target
        format
        content
        createIfMissing
        ;
    }) (lib.filterAttrs (_: entry: entry.enable) attrs);
in
{
  imports = [
    baseAppModule
    (lib.mkRenamedOptionModule [ "files" "install" ] [ "files" "game" "place" ])
    (lib.mkRenamedOptionModule [ "removeFiles" "install" ] [ "files" "game" "remove" ])
    (lib.mkRenamedOptionModule [ "removeFiles" "prefix" ] [ "files" "prefix" "remove" ])
  ];

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

        The app must be installed for this to be applied. When unset again, Steam's default update behaviour is restored.
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

    files.game.place = lib.mkOption {
      type = types.attrsOf placeSubmodule;
      default = { };
      example = lib.literalExpression ''
        {
          "BepInEx/plugins/plugin.dll".source = ./plugin.dll;
          "mod.cfg" = {
            source = ./mod.cfg;
            mode = "seed";
          };
        }
      '';
      description = ''
        Files to place in the game's install directory, keyed by path relative to it. The app must be installed for these to be applied.
      '';
    };

    files.game.remove = lib.mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "movies/intro.bik" ];
      description = ''
        Paths in the game's install directory to remove, relative to it. A directory is removed recursively. Removed files are restored when the entry is unset.
      '';
    };

    files.game.patch = lib.mkOption {
      type = types.attrsOf patchSubmodule;
      default = { };
      example = lib.literalExpression ''
        {
          "Engine/Config/BaseEngine.ini" = {
            format = "ini";
            content.SystemSettings."r.Tonemapper.Sharpen" = 2;
          };
        }
      '';
      description = ''
        Files in the game's install directory to patch by merging keys into them. The app must be installed for these to be applied.
      '';
    };

    files.prefix.place = lib.mkOption {
      type = types.attrsOf placeSubmodule;
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

    files.prefix.remove = lib.mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Paths in the app's Proton prefix to remove, relative to the prefix root.
      '';
    };

    files.prefix.patch = lib.mkOption {
      type = types.attrsOf patchSubmodule;
      default = { };
      example = lib.literalExpression ''
        {
          "drive_c/users/steamuser/AppData/Local/game/settings.json" = {
            format = "json";
            content.graphics.fullscreen = true;
          };
        }
      '';
      description = ''
        Files in the app's Proton prefix to patch by merging keys into them. The app must have been launched once for the prefix to exist.
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
    files = mkFileOps "game" config.files.game.place ++ mkFileOps "prefix" config.files.prefix.place;
    removeFiles =
      mkRemoveOps "game" config.files.game.remove ++ mkRemoveOps "prefix" config.files.prefix.remove;
    patches =
      mkPatchOps "game" config.files.game.patch ++ mkPatchOps "prefix" config.files.prefix.patch;
  };

  # surface the per-file mode migration warnings (place submodule warnings are not collected otherwise)
  config.warnings = lib.concatMap (entry: entry.warnings) (
    lib.attrValues config.files.game.place ++ lib.attrValues config.files.prefix.place
  );
}
