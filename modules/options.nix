{ self, format }:
{
  lib,
  config,
  options,
  pkgs,
  osConfig ? null,
  ...
}:
let
  inherit (lib) types;
  inherit
    (import ../lib/context.nix {
      inherit
        lib
        config
        osConfig
        format
        ;
    })
    cfg
    isNixos
    osSteamConfig
    layered
    launchShellPath
    enabledApps
    enabledNonSteamApps
    allApps
    ;

  explicitDefinitions =
    opts:
    lib.concatMapAttrs (
      name: opt:
      if lib.isOption opt then
        lib.optionalAttrs (
          (opt.visible or true) != false
          && !(opt.internal or false)
          && !(opt.readOnly or false)
          && opt.highestPrio < 1500
        ) { ${name} = lib.mkMerge (map (lib.mkOverride opt.highestPrio) opt.definitions); }
      else
        let
          sub = explicitDefinitions opt;
        in
        lib.optionalAttrs (sub != { }) { ${name} = sub; }
    ) opts;

  removedOption = lib.mkOption {
    type = types.unspecified;
    default = null;
    visible = false;
  };
  renamed = lib.concatLists [
    (lib.optional (
      config.programs.steam.config != null
    ) "programs.steam.config was renamed to programs.steam-config.")
    (lib.optional (
      cfg.package != null
    ) "programs.steam-config: `package` was split into `packages.patcher` and `packages.launch`.")
  ];

  envLib = import ../lib/env.nix { inherit lib; };
  appModule = lib.modules.importApply ./submodules/app.nix { inherit lib pkgs removedOption; };
  filesModule = lib.modules.importApply ./submodules/files.nix { inherit lib pkgs removedOption; };

  mkApps =
    kind:
    types.attrsOf (
      types.submoduleWith {
        modules = [
          appModule
          filesModule
        ];
        specialArgs = {
          inherit kind;
          steamConfig = cfg;
        };
      }
    );
in
{
  options.programs.steam.config = removedOption;

  options.programs.steam-config = {
    enable = lib.mkEnableOption "declarative Steam configuration";

    package = removedOption;

    onSteamRunning = lib.mkOption {
      type = types.enum [
        "wait"
        "close"
        "force-close"
        "skip"
      ];
      default = "wait";
      example = "close";
      description = ''
        What to do when configuration changes need to be written while Steam is running:

        - `"wait"`: wait for Steam to exit, then apply the changes
        - `"close"`: close Steam and apply the changes, waiting for any running games to exit first
        - `"force-close"`: close Steam and apply the changes immediately, even if a game is running
        - `"skip"`: skip writing, and apply the changes on the next activation
      '';
    };

    launchShell = lib.mkOption {
      type = types.path;
      default = if layered then osSteamConfig.launchShell else launchShellPath;
      internal = true;
      visible = false;
    };

    packages = {
      patcher = lib.mkOption {
        type = types.package;
        default = self.packages.${pkgs.stdenv.hostPlatform.system}.steam-config-patcher;
        defaultText = lib.literalMD "`steam-config-patcher` from this flake";
        description = "The patcher, which writes the configuration into Steam's files while Steam is closed.";
      };

      launch = lib.mkOption {
        type = types.package;
        default =
          if layered then
            osSteamConfig.packages.launch
          else
            self.packages.${pkgs.stdenv.hostPlatform.system}.steam-config-launch;
        defaultText = lib.literalMD "`steam-config-launch` from this flake, or the NixOS value under Home Manager when the NixOS module is enabled";
        description = "The launch step Steam runs every game through, which applies an app's launch options and serves its files. It is on `PATH` for `steam-config-launch show <app>`. Under Home Manager with the NixOS module enabled, Steam runs the NixOS value.";
      };
    };

    libraryFolders = lib.mkOption {
      type = types.listOf types.path;
      default = [ ];
      example = [ "/mnt/games/SteamLibrary" ];
      description = "Steam library folders added to the client, as in Settings > Storage. A folder that does not exist yet is created. Removing one here removes it from Steam when this module added it, and its games stay on disk.";
    };

    env = lib.mkOption {
      inherit (envLib) type;
      default = { };
      example = lib.literalExpression ''
        {
          PROTON_ENABLE_WAYLAND = 1;
          TZ = null;
        }
      '';
      description = ''
        Environment variables for every game and non-Steam app Steam launches, including ones not configured here. Set a value to `null` to unset that variable. `true` is exported as `1`, `false` as an empty string and a float such as `1.5` as `1.5`. An app's own `env` takes precedence.
      '';
    };

    defaultCompatTool = lib.mkOption {
      type = with types; nullOr (either str package);
      default = null;
      example = "proton_experimental";
      description = ''
        Compatibility tool for Steam Play, as in Settings > Compatibility. Either the internal name of an installed tool or a package containing one.
      '';
    };

    displayRatesAsBits = lib.mkOption {
      type = with types; nullOr bool;
      default = null;
      example = false;
      description = ''
        Whether download rates are shown in bits per second.

        - `false`: MB/s (bytes)
        - `true`: Mb/s (bits)
        - `null`: the existing Steam setting is left alone
      '';
    };

    desktopUiScale = lib.mkOption {
      type = with types; nullOr (numbers.between 0.5 2.0);
      default = null;
      example = 1.25;
      description = ''
        Scale of the Steam desktop interface, where `1.0` is the unscaled size. `null` leaves the existing Steam setting alone.
      '';
    };

    desktopEntries.enable = lib.mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = "Install a desktop entry for every configured app, launching it through Steam.";
    };

    desktopEntries.libraryIcons = lib.mkOption {
      type = types.bool;
      default = true;
      example = false;
      description = "Use each Steam app's icon from the library for its desktop entry. An app can opt out with `desktopEntry.useLibraryIcon`, and `desktopEntry.icon` set explicitly takes precedence.";
    };

    notifications = lib.mkOption {
      type = types.bool;
      default = true;
      example = false;
      description = ''
        Send desktop notifications for slow launch steps, such as installing winetricks verbs, and for anything that stops the configuration being applied.
      '';
    };

    apps = lib.mkOption {
      type = mkApps "steam";
      default = { };
      description = ''
        Configuration per Steam app, indexed by its app ID or by a name of your choosing with `id` set.
      '';
    };

    nonSteamApps = lib.mkOption {
      type = mkApps "non-steam";
      default = { };
      description = ''
        Configuration per non-Steam app, indexed by a name of your choosing. The name seeds the shortcut's ID unless `seed` is set, so renaming it replaces the shortcut with a new one.
      '';
    };

    notifySend = lib.mkOption {
      type = types.nullOr types.str;
      default = if cfg.notifications then lib.getExe' pkgs.libnotify "notify-send" else null;
      readOnly = true;
      internal = true;
      visible = false;
    };

    definitions = lib.mkOption {
      type = types.raw;
      default = removeAttrs (explicitDefinitions options.programs.steam-config) [ "enable" ];
      readOnly = true;
      internal = true;
      visible = false;
    };
  };

  config = lib.mkMerge [
    {
      assertions = map (m: {
        assertion = false;
        message = m;
      }) renamed;
    }

    (lib.optionalAttrs (!isNixos) {
      programs.steam-config = if layered then osSteamConfig.definitions else { };
    })

    (lib.mkIf cfg.enable {
      assertions =
        import ../lib/assertions.nix { inherit lib enabledApps enabledNonSteamApps; }
        ++ lib.concatMap (app: app.assertions) allApps;
      warnings = lib.concatMap (app: app.warnings) allApps;
    })
  ];
}
