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
  envLib = import ../../lib/env.nix { inherit lib; };
  inherit (import ../../lib/shortcut-id.nix { inherit lib; })
    slugify
    appIdMin
    appIdMax
    seedToId
    mkShortcutGameId
    ;

  displayName = if config.name == name then name else "${config.name} (${name})";
  libraryIconName = "steam-config-nix-${config.appKey}";
  appPath = "programs.steam-config.${if isSteam then "apps" else "nonSteamApps"}.${name}";

  hasOptions =
    config.env != { }
    || config.wrappers != [ ]
    || config.args != [ ]
    || config.preHook != ""
    || config.dllOverrides != { }
    || config.rawLaunchOptions != null
    || config.winetricks != [ ]
    || config.prefixPath != null
    || config.systemd.enable
    || config.filesSpec != null;

  scopeProperties = {
    Description = displayName;
    Wants = config.systemd.target.unitName;
    After = config.systemd.target.unitName;
  }
  // config.systemd.scope.properties;

  renderProperty =
    value: if lib.isBool value then (if value then "yes" else "no") else toString value;

  launchSpec = {
    version = 1;
    key = config.appKey;
    appId = config.id;
    kind = if isSteam then "steam" else "nonSteam";
    name = displayName;
    inherit (steamConfig) notifySend;
    env = envLib.toSpec config.env;
    inherit (config)
      dllOverrides
      rawLaunchOptions
      args
      wrappers
      ;
    prefixPath = if config.prefixPath == null then null else toString config.prefixPath;
    winetricks =
      if config.winetricks == [ ] then
        null
      else
        {
          verbs = config.winetricks;
          protontricks = lib.getExe' pkgs.protontricks "protontricks";
          # protontricks finds the prefix by app id under the library, so the relocated one is bound over it
          bwrap = if config.prefixPath != null then lib.getExe' pkgs.bubblewrap "bwrap" else null;
        };
    preHook = if config.preHook == "" then null else config.preHook;
    shell = if config.preHook == "" then null else lib.getExe pkgs.bash;
    envProgram =
      if config.wrappers == [ ] && config.preHook == "" then null else lib.getExe' pkgs.coreutils "env";
    scope =
      if config.systemd.enable then
        {
          systemdRun = lib.getExe' pkgs.systemd "systemd-run";
          systemctl = lib.getExe' pkgs.systemd "systemctl";
          properties = lib.mapAttrs (_: renderProperty) scopeProperties;
        }
      else
        null;
    files = if config.filesSpec == null then null else "${config.filesSpec}";
  };
in
{
  options = {
    enable = lib.mkOption {
      type = types.bool;
      default = true;
      description = "Whether this app's configuration is applied.";
    };

    name = lib.mkOption {
      type = types.str;
      default = name;
      defaultText = lib.literalMD "the attribute name";
      description = "Display name, used for a non-Steam app's entry in the Steam library, in notifications, the systemd target and the desktop entry.";
    };

    compatTool = lib.mkOption {
      type = with types; nullOr (either str package);
      default = null;
      example = "proton_experimental";
      description = ''
        Compatibility tool to run this app with, as in Properties > Compatibility. Either the internal name of an installed tool or a package containing one.
      '';
    };

    overlay = lib.mkOption {
      type = with types; nullOr bool;
      default = null;
      example = false;
      description = "Whether the Steam Overlay is enabled while this app runs. `null` leaves the existing setting alone.";
    };

    artwork = lib.mkOption {
      type = types.submodule {
        options =
          lib.genAttrs
            (
              [
                "cover"
                "header"
                "hero"
                "logo"
              ]
              ++ lib.optional (!isSteam) "icon"
            )
            (
              slot:
              lib.mkOption {
                type = types.nullOr types.path;
                default = null;
                description =
                  if slot == "icon" then
                    "Icon for the app in the library and in its desktop entry."
                  else
                    "Custom ${slot} image for the library.";
              }
            );
      };
      default = { };
      description = "Custom library artwork.";
    };

    env = lib.mkOption {
      inherit (envLib) type;
      default = { };
      example = lib.literalExpression ''
        {
          DXVK_HUD = "fps,gpuload";
          PROTON_ENABLE_WAYLAND = 1;
          TZ = null;
        }
      '';
      description = "Environment variables exported for this app's launch. Set a value to `null` to unset that variable. `true` is exported as `1`, `false` as an empty string and a float such as `1.5` as `1.5`.";
    };

    wrappers = lib.mkOption {
      type = types.listOf (types.coercedTo types.package lib.getExe types.str);
      default = [ ];
      example = lib.literalExpression ''
        [
          (lib.getExe pkgs.gamescope)
          "-f"
          "--"
          (lib.getExe' pkgs.mangohud "mangohud")
        ]
      '';
      description = "Commands the launch is wrapped with, outermost first. Each element is one argument, so a command's flags follow it as separate elements.";
    };

    args = lib.mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [
        "-novid"
        "--launcher-skip"
      ];
      description = "Arguments appended to the app's command line.";
    };

    preHook = lib.mkOption {
      type = types.lines;
      default = "";
      description = ''
        Bash run by the launch step before the app starts, with `env`, `dllOverrides` and `prefixPath` applied. `cmdline` holds the command line Steam built, and the `wrappers` and `args` arrays hold those options. Changes to all three carry into the launch. Any exit before the end stops the launch, with a notification for a non-zero code.
      '';
    };

    dllOverrides = lib.mkOption {
      type = types.attrsOf (
        types.enum [
          "n"
          "b"
          "n,b"
          "b,n"
          "disabled"
        ]
      );
      default = { };
      example = {
        winhttp = "n,b";
      };
      description = "Wine DLL overrides, exported as `WINEDLLOVERRIDES`.";
    };

    rawLaunchOptions = lib.mkOption {
      type = with types; nullOr str;
      default = null;
      example = "gamemoderun %command% -novid";
      description = ''
        A launch options string in Steam's own syntax, applied around the command line. Without `%command%` it is appended as arguments.
      '';
    };

    winetricks = lib.mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "vcrun2022" ];
      description = "Winetricks verbs installed into the app's Proton prefix on its next launch, through protontricks.";
    };

    prefixPath = lib.mkOption {
      type = with types; nullOr path;
      default = null;
      example = "/mnt/games/prefixes/438100";
      description = "Directory used as `STEAM_COMPAT_DATA_PATH`, the one holding the app's `pfx`. Its parent must already exist.";
    };

    systemd = {
      enable = lib.mkOption {
        type = types.bool;
        default = false;
        example = true;
        description = ''
          Launch the app in a transient scope that activates `steam-app-<name>.target`, and a shared `steam-app.target` that is active while any such app is running. Other units can be tied to those targets.
        '';
      };

      target.name = lib.mkOption {
        type = types.str;
        default = slugify config.name;
        defaultText = lib.literalMD "the app's `name`, lowercased with `-` for anything outside `a-z0-9`";
        description = "The part after `steam-app-` in the target's unit name.";
      };

      target.unitName = lib.mkOption {
        type = types.str;
        default = "steam-app-${config.systemd.target.name}.target";
        readOnly = true;
        description = "The full unit name of this app's target.";
      };

      target.unitConfig = lib.mkOption {
        type = types.attrsOf (
          types.oneOf [
            types.str
            types.int
            types.bool
            (types.listOf types.str)
          ]
        );
        default = { };
        description = ''
          Extra `[Unit]` settings for the target. The generated target sets `Description`, `Documentation`, `StopWhenUnneeded`, `RefuseManualStart`, `RefuseManualStop` and its dependencies on `steam-app.target`.
        '';
      };

      scope.properties = lib.mkOption {
        type = types.attrsOf (
          types.oneOf [
            types.str
            types.int
            types.bool
          ]
        );
        default = { };
        example = {
          Slice = "games.slice";
          CPUWeight = 150;
        };
        description = ''
          Properties set on the transient scope the app runs in, passed to `systemd-run --property`. `OnFailure` is never triggered, because a scope's result does not follow the exit status of the processes inside it.
        '';
      };
    };

    desktopEntry = {
      enable = lib.mkOption {
        type = types.bool;
        default = steamConfig.desktopEntries.enable;
        defaultText = lib.literalMD "`programs.steam-config.desktopEntries.enable`";
        description = "Whether a desktop entry that launches the app through Steam is installed.";
      };
      name = lib.mkOption {
        type = types.str;
        default = config.name;
        defaultText = lib.literalMD "the app's `name`";
        description = "Name shown in application menus.";
      };
      genericName = lib.mkOption {
        type = with types; nullOr str;
        default = null;
        description = "Generic name shown next to the name in some menus.";
      };
      comment = lib.mkOption {
        type = with types; nullOr str;
        default = null;
        description = "Tooltip text.";
      };
      icon = lib.mkOption {
        type = with types; nullOr (either str path);
        default =
          if isSteam then
            (if config.desktopEntry.useLibraryIcon then libraryIconName else null)
          else
            config.artwork.icon;
        defaultText = lib.literalMD "the app's library icon when `useLibraryIcon` is set, a non-Steam app's `artwork.icon`, otherwise none";
        description = "Icon name or image path.";
      };
      categories = lib.mkOption {
        type = types.listOf types.str;
        default = [ "Game" ];
        description = "Desktop entry categories.";
      };
    }
    // lib.optionalAttrs isSteam {
      useLibraryIcon = lib.mkOption {
        type = types.bool;
        default = steamConfig.desktopEntries.libraryIcons;
        defaultText = lib.literalMD "`programs.steam-config.desktopEntries.libraryIcons`";
        description = "Use the app's icon from the Steam library. It comes from Steam's cache, so an app Steam has not loaded yet gets the Steam icon until the next activation after it has.";
      };
    };

    key = lib.mkOption {
      type = types.str;
      default = slugify name;
      readOnly = true;
      internal = true;
      visible = false;
    };

    appKey = lib.mkOption {
      type = types.str;
      default = if isSteam then toString config.id else config.key;
      readOnly = true;
      internal = true;
      visible = false;
    };

    launchSpec = lib.mkOption {
      type = types.nullOr types.attrs;
      default = if hasOptions then launchSpec else null;
      readOnly = true;
      internal = true;
      visible = false;
    };

    steamRunId = lib.mkOption {
      type = types.str;
      default = if isSteam then toString config.id else mkShortcutGameId config.id;
      readOnly = true;
      internal = true;
      visible = false;
    };

    warnings = lib.mkOption {
      type = types.listOf types.str;
      default = [ ];
      internal = true;
      visible = false;
    };

    assertions = lib.mkOption {
      type = types.listOf types.attrs;
      default = [ ];
      internal = true;
      visible = false;
    };
  }
  // lib.optionalAttrs isSteam {
    id = lib.mkOption {
      type = types.ints.positive;
      default =
        if lib.match "[0-9]+" name != null then
          lib.toInt name
        else
          throw "programs.steam-config.apps.${name} needs `id`, the attribute name is not an app ID";
      defaultText = lib.literalMD "the attribute name, when it is an app ID";
      example = 438100;
      description = "The app ID, found in the store page URL.";
    };

    betaBranch = lib.mkOption {
      type = with types; nullOr str;
      default = null;
      example = "beta";
      description = "The beta branch to opt into, as in Properties > Betas. `\"public\"` leaves any beta.";
    };

    language = lib.mkOption {
      type = with types; nullOr str;
      default = null;
      example = "german";
      description = ''
        Language for this app, as a Steam API language code such as `"english"`, `"german"` or `"schinese"`.
      '';
    };

    updateBehavior = lib.mkOption {
      type =
        with types;
        nullOr (enum [
          "default"
          "onLaunch"
          "highPriority"
        ]);
      default = null;
      example = "onLaunch";
      description = ''
        When Steam downloads updates for this app, as in Properties > Updates.

        - `"default"`: Steam's own choice, "Always keep this game updated"
        - `"onLaunch"`: "Only update this game when I launch it"
        - `"highPriority"`: "High priority", updated before other games
      '';
    };

    allowDownloadsWhileRunning = lib.mkOption {
      type =
        with types;
        nullOr (enum [
          "default"
          "always"
          "never"
        ]);
      default = null;
      example = "always";
      description = "Whether other downloads continue while this app runs, as in Properties > Updates.";
    };

    steamInput = lib.mkOption {
      type =
        with types;
        nullOr (enum [
          "default"
          "enable"
        ]);
      default = null;
      example = "enable";
      description = "The Steam Input setting for this app, as in Properties > Controller.";
    };
  }
  // lib.optionalAttrs (!isSteam) {
    target = lib.mkOption {
      type = with types; coercedTo package lib.getExe (either path str);
      example = lib.literalExpression "pkgs.vintagestory";
      description = "The executable Steam launches, as a package or an absolute path.";
    };

    startIn = lib.mkOption {
      type = with types; nullOr str;
      default = dirOf (toString config.target);
      defaultText = lib.literalExpression "dirOf target";
      description = "Working directory for the app.";
    };

    inVrLibrary = lib.mkOption {
      type = with types; nullOr bool;
      default = null;
      example = true;
      description = "Whether the app is listed in the VR library. `null` leaves the existing setting alone.";
    };

    hidden = lib.mkOption {
      type = with types; nullOr bool;
      default = null;
      example = true;
      description = "Whether the shortcut is hidden in the library. `null` leaves the existing setting alone.";
    };

    seed = lib.mkOption {
      type = types.str;
      default = name;
      defaultText = lib.literalMD "the attribute name";
      example = "vintage-story";
      description = "Seed the shortcut's ID is derived from. Changing it changes the ID, which means a new Wine prefix for a Proton app and a fresh shortcut with no artwork or play time.";
    };

    id = lib.mkOption {
      type = types.ints.between appIdMin appIdMax;
      default = seedToId config.seed;
      defaultText = lib.literalMD "an ID derived from the seed";
      example = 2496815253;
      description = "Steam App ID for the shortcut. Set it only to match an ID Steam already assigned.";
    };

    isHidden = removedOption;
    allowOverlay = removedOption;
  };

  config.assertions =
    map
      (m: {
        assertion = false;
        message = "${appPath}: ${m}";
      })
      (
        lib.optionals (!isSteam) (
          lib.concatLists [
            (lib.optional (config.isHidden != null) "`isHidden` was renamed to `hidden`.")
            (lib.optional (config.allowOverlay != null) "`allowOverlay` was renamed to `overlay`.")
          ]
        )
        ++
          lib.optional (config.systemd.enable && config.env ? STEAM_LAUNCH_WRAPPER_SCOPE)
            "`env.STEAM_LAUNCH_WRAPPER_SCOPE` has no effect with `systemd.enable`, which always turns Steam's scope off."
        ++ lib.optional (
          config.env ? WINEDLLOVERRIDES && config.dllOverrides != { }
        ) "`env.WINEDLLOVERRIDES` is replaced by `dllOverrides`, set the overrides there instead."
      );
}
