{
  lib,
  pkgs,
  removedOption,
}:
{
  name,
  config,
  kind,
  steamConfig,
  ...
}:
let
  inherit (lib) types;
  isSteam = kind == "steam";
  appPath = "programs.steam-config.${if isSteam then "apps" else "nonSteamApps"}.${name}";
  appKey = config.appKey;

  normalise =
    p: lib.concatStringsSep "/" (lib.filter (part: part != "" && part != ".") (lib.splitString "/" p));
  unsafe = p: lib.hasPrefix "/" p || lib.elem ".." (lib.splitString "/" p) || normalise p == "";
  within = path: dir: path == dir || lib.hasPrefix "${dir}/" path;

  resolveSource =
    entry:
    if entry.text != null then pkgs.writeText "steam-config-nix-file" entry.text else entry.source;

  overlayEntry = types.submodule (
    { name, ... }: {
      options = {
        enable = lib.mkOption {
          type = types.bool;
          default = true;
          description = "Whether this entry is applied.";
        };
        source = lib.mkOption {
          type = types.nullOr types.path;
          default = null;
          example = lib.literalExpression "./mods/plugin.dll";
          description = "File or directory the game sees at `target`. Exactly one of `source` or `text` is set.";
        };
        text = lib.mkOption {
          type = types.nullOr types.lines;
          default = null;
          description = "Contents of a file the game sees at `target`. Exactly one of `source` or `text` is set.";
        };
        target = lib.mkOption {
          type = types.str;
          default = name;
          defaultText = lib.literalMD "the attribute name";
          example = "BepInEx/plugins/plugin.dll";
          description = "Path relative to the location's root.";
        };
        executable = lib.mkOption {
          type = types.nullOr types.bool;
          default = null;
          example = true;
          description = "Whether the file is executable. `null` keeps the source's bit. On a directory, applies to every file in it.";
        };
        readOnly = lib.mkOption {
          type = types.bool;
          default = false;
          example = true;
          description = "The game cannot write to or replace the file. Use it for a file the game overwrites at startup.";
        };
      };
    }
  );

  writeDefaultEntry = types.submodule (
    { name, ... }: {
      options = {
        enable = lib.mkOption {
          type = types.bool;
          default = true;
          description = "Whether this entry is applied.";
        };
        source = lib.mkOption {
          type = types.nullOr types.path;
          default = null;
          example = lib.literalExpression "./MoreCompany.cfg";
          description = "File or directory written when the target does not exist. Exactly one of `source` or `text` is set.";
        };
        text = lib.mkOption {
          type = types.nullOr types.lines;
          default = null;
          description = "Contents written when the target does not exist. Exactly one of `source` or `text` is set.";
        };
        target = lib.mkOption {
          type = types.str;
          default = name;
          defaultText = lib.literalMD "the attribute name";
          example = "BepInEx/config/MoreCompany.cfg";
          description = "Path relative to the location's root.";
        };
        executable = lib.mkOption {
          type = types.nullOr types.bool;
          default = null;
          example = true;
          description = "Whether the written file is executable. `null` keeps the source's bit. On a directory, applies to every file in it.";
        };
      };
    }
  );

  writeKeysEntry = types.submodule (
    { name, ... }: {
      options = {
        enable = lib.mkOption {
          type = types.bool;
          default = true;
          description = "Whether this entry is applied.";
        };
        target = lib.mkOption {
          type = types.str;
          default = name;
          defaultText = lib.literalMD "the attribute name";
          example = "Engine/Config/BaseEngine.ini";
          description = "Path relative to the location's root.";
        };
        format = lib.mkOption {
          type = types.enum [
            "ini"
            "json"
            "registry"
            "unityPrefs"
            "keyvalue"
            "sourceConvars"
          ];
          example = "ini";
          description = ''
            How the file is read and written back. Keys not named in `content` are kept as they are.

            - `"ini"`: `content` maps section names to keys. A list value writes the key once per element, which is how Unreal stores a multi-valued setting. Duplicate keys that are not named are kept.
            - `"json"`: `content` is deep merged into the file.
            - `"registry"`: a Wine registry file such as `user.reg`. `content` maps a key path (`/` or `\\` separated) to value names. A string is written as `REG_SZ`, an integer or boolean as `REG_DWORD`.
            - `"unityPrefs"`: Unity PlayerPrefs in a Wine `user.reg`. `content` maps `Software/<Company>/<Product>` to plain PlayerPrefs keys. Each key is hashed the way Unity does and the value encoded by its type: integer, float, boolean or string.
            - `"keyvalue"`: a Valve KeyValues (VDF) file. `content` is deep merged into the file. Comments are not kept.
            - `"sourceConvars"`: a Source engine console config such as `autoexec.cfg`. `content` maps console variables to values. Binds, aliases and comments are kept. A boolean is written as `1` or `0`.
          '';
        };
        content = lib.mkOption {
          type = types.attrsOf types.anything;
          example = lib.literalExpression ''{ "Engine.Console".ConsoleKey = "F9"; }'';
          description = "Keys to set, shaped per `format`.";
        };
        createIfMissing = lib.mkOption {
          type = types.bool;
          default = false;
          example = true;
          description = "Write a new file holding only these keys when the target does not exist. Otherwise a missing file is skipped until the game creates it.";
        };
      };
    }
  );

  location =
    loc:
    types.submodule (
      { config, ... }:
      let
        locPath = "${appPath}.files.${loc}";
        entries = family: lib.filter (e: e.enable) (lib.attrValues config.${family});
        overlayTargets = map (e: normalise e.target) (entries "overlay");
        hideTargets = map normalise config.hide;
        passthroughDirs = map normalise config.passthrough;
        writeDefaultTargets = map (e: normalise e.target) (entries "writeDefault");
        writeKeysTargets = map (e: normalise e.target) (entries "writeKeys");
        readOnlyDirs = map (e: normalise e.target) (lib.filter (e: e.readOnly) (entries "overlay"));
        families = {
          overlay = overlayTargets;
          hide = hideTargets;
          writeDefault = writeDefaultTargets;
          writeKeys = writeKeysTargets;
        };
        allTargets =
          overlayTargets ++ hideTargets ++ passthroughDirs ++ writeDefaultTargets ++ writeKeysTargets;
        duplicated = lib.concatMap (
          a:
          lib.concatMap (
            b:
            lib.optionals (a < b) (
              map (t: "`${t}` is declared under both `${a}` and `${b}`. A path can only be in one.") (
                lib.intersectLists families.${a} families.${b}
              )
            )
          ) (lib.attrNames families)
        ) (lib.attrNames families);
        shadowed = lib.concatMap (
          dir:
          map (
            t:
            "`${t}` is served by `overlay` but `${dir}` is in `passthrough`, so the game would see the real directory instead. Drop one."
          ) (lib.filter (t: within t dir) overlayTargets)
          ++ map (
            t: "`${t}` is in `hide` but `${dir}` is in `passthrough`, so the game would still see it. Drop one."
          ) (lib.filter (t: within t dir) hideTargets)
        ) passthroughDirs;
        unwritable = lib.concatMap (
          dir:
          map (t: "`${t}` is written under `${dir}`, which is `readOnly`.") (
            lib.filter (t: within t dir && t != dir) (writeDefaultTargets ++ writeKeysTargets)
          )
        ) readOnlyDirs;
        oneSource =
          lib.concatMap
            (
              family:
              map (e: "`${family}.${e.target}` needs exactly one of `source` or `text`.") (
                lib.filter (e: (e.source == null) == (e.text == null)) (entries family)
              )
            )
            [
              "overlay"
              "writeDefault"
            ];
        renamed = lib.concatLists [
          (lib.optional (config.place != null)
            "`place` was renamed: `mode = \"enforce\"` is `overlay`, `\"lock\"` is `overlay` with `readOnly = true`, `\"seed\"` is `writeDefault`."
          )
          (lib.optional (config.remove != null) "`remove` was renamed to `hide`.")
          (lib.optional (config.patch != null) "`patch` was renamed to `writeKeys`.")
        ];
        messages =
          map (t: "`${t}` must be a relative path inside the ${loc}.") (lib.filter unsafe allTargets)
          ++ duplicated
          ++ shadowed
          ++ unwritable
          ++ oneSource
          ++ renamed;
        mkEntries =
          family:
          map (e: {
            target = normalise e.target;
            source = "${resolveSource e}";
            inherit (e) executable;
          }) (lib.filter (e: resolveSource e != null) (entries family));
      in
      {
        options = {
          overlay = lib.mkOption {
            type = types.attrsOf overlayEntry;
            default = { };
            example = lib.literalExpression ''
              {
                "winhttp.dll".source = ./bepinex/winhttp.dll;
                "BepInEx/core".source = ./bepinex/BepInEx/core;
              }
            '';
            description = ''
              Files and directories the game sees at the given paths, served for the session. The real files are not changed, and a missing parent directory is created. Anything the game writes under a served path persists in `$XDG_DATA_HOME/steam-config-nix/apps/<app>/writes/${loc}`, where `<app>` is the app ID, or for a non-Steam app its attribute name lowercased with `-` for anything outside `a-z0-9`.
            '';
          };
          hide = lib.mkOption {
            type = types.listOf types.str;
            default = [ ];
            example = [ "movies/intro.bik" ];
            description = "Paths the game does not see. The real files stay.";
          };
          passthrough = lib.mkOption {
            type = types.listOf types.str;
            default = [ ];
            example = [ "Saves" ];
            description = ''
              Directories the game writes to in place instead of under `$XDG_DATA_HOME/steam-config-nix`, for saves and configs that Steam Cloud syncs or that you edit by hand. A served or hidden path cannot be inside one. The directory is created when it does not exist.
            '';
          };
          writeDefault = lib.mkOption {
            type = types.attrsOf writeDefaultEntry;
            default = { };
            example = lib.literalExpression ''
              {
                "BepInEx/config/MoreCompany.cfg".source = ./MoreCompany.cfg;
              }
            '';
            description = ''
              Files written once, when the target does not exist, where the game sees them. The game and you own them from then on. A changed `source` is not written until the file is deleted.
            '';
          };
          writeKeys = lib.mkOption {
            type = types.attrsOf writeKeysEntry;
            default = { };
            example = lib.literalExpression ''
              {
                "Engine.ini" = {
                  format = "ini";
                  content."Engine.Console".ConsoleKey = "F9";
                };
              }
            '';
            description = ''
              Keys set in files the game owns, before every launch, where the game sees them. Other keys are kept. A copy of each file as it was before the first write is kept under `$XDG_DATA_HOME/steam-config-nix/apps/<app>/originals/${loc}`, next to the `writes` directory. Removing an entry leaves the keys in place.
            '';
          };
          place = removedOption;
          remove = removedOption;
          patch = removedOption;

          messages = lib.mkOption {
            type = types.listOf types.str;
            default = map (m: "${locPath}: ${m}") messages;
            readOnly = true;
            internal = true;
            visible = false;
          };
          spec = lib.mkOption {
            type = types.nullOr types.attrs;
            default =
              if allTargets == [ ] then
                null
              else
                {
                  layer =
                    if overlayTargets == [ ] then
                      null
                    else
                      pkgs.runCommand "steam-config-nix-files-${appKey}-${loc}" { } (
                        lib.concatMapStrings (e: ''
                          mkdir -p "$out"/${lib.escapeShellArg (dirOf e.target)}
                          cp -r ${e.source} "$out"/${lib.escapeShellArg e.target}
                          ${lib.optionalString (e.executable != null)
                            ''find "$out"/${lib.escapeShellArg e.target} -type f -exec chmod ${
                              if e.executable then "+x" else "-x"
                            } {} +''
                          }
                        '') (mkEntries "overlay")
                      );
                  overlay = map (e: {
                    target = normalise e.target;
                    inherit (e) readOnly;
                  }) (entries "overlay");
                  hide = hideTargets;
                  passthrough = passthroughDirs;
                  writeDefault = mkEntries "writeDefault";
                  writeKeys = map (e: {
                    target = normalise e.target;
                    inherit (e) format content createIfMissing;
                  }) (entries "writeKeys");
                };
            readOnly = true;
            internal = true;
            visible = false;
          };
        };
      }
    );

  locations = lib.filterAttrs (_: l: l.spec != null) (
    lib.optionalAttrs isSteam { game = config.files.game; } // { prefix = config.files.prefix; }
  );
  spec = {
    key = appKey;
    inherit (config) name;
    appId = if isSteam then config.id else null;
    bwrap = lib.getExe' pkgs.bubblewrap "bwrap";
    inherit (steamConfig) notifySend;
    locations = lib.mapAttrs (_: l: l.spec) locations;
  };
in
{
  options = {
    files =
      lib.optionalAttrs isSteam {
        game = lib.mkOption {
          type = location "game";
          default = { };
          description = "Files in the game's install directory.";
        };
      }
      // {
        prefix = lib.mkOption {
          type = location "prefix";
          default = { };
          description = "Files in the app's Proton prefix, relative to its `pfx` directory. Skipped until the prefix exists.";
        };
      };

    filesSpec = lib.mkOption {
      type = types.nullOr types.package;
      default =
        if locations == { } then
          null
        else
          pkgs.writeText "steam-config-nix-files-${spec.key}.json" (lib.toJSON spec);
      readOnly = true;
      internal = true;
      visible = false;
    };
  };

  config.assertions = map (m: {
    assertion = false;
    message = m;
  }) (lib.concatMap (l: l.messages) (lib.attrValues config.files));
}
