{
  lib,
  pkgs,
  dataDir,
}:
{
  name,
  config,
  steamConfig,
  ...
}:
let
  inherit (lib) types;
  baseAppWrapperModule = lib.modules.importApply ./base-app-wrapper.nix { inherit lib pkgs dataDir; };

  mkDllOverrides =
    overrides:
    lib.concatStringsSep ";" (
      lib.mapAttrsToList (dll: mode: "${dll}=${if mode == "disabled" then "" else mode}") overrides
    );

  slugify =
    s:
    lib.concatStringsSep "-" (
      lib.filter (part: part != "") (
        lib.splitString "-" (
          lib.stringAsChars (c: if lib.match "[a-z0-9]" c != null then c else "-") (lib.toLower s)
        )
      )
    );

in
{
  imports = [
    baseAppWrapperModule

    # declares the `warnings` and `assertions` options this submodule collects upward
    "${pkgs.path}/nixos/modules/misc/assertions.nix"
    (lib.mkRenamedOptionModule [ "launchOptions" "env" ] [ "env" ])
    (lib.mkRenamedOptionModule [ "launchOptions" "args" ] [ "args" ])
    (lib.mkRenamedOptionModule [ "launchOptions" "wrappers" ] [ "wrappers" ])
    (lib.mkRenamedOptionModule [ "launchOptions" "preHook" ] [ "preHook" ])
    (lib.mkRenamedOptionModule [ "launchOptionsStr" ] [ "rawLaunchOptions" ])
  ];

  options = {
    enable = lib.mkOption {
      type = types.bool;
      default = true;
      example = false;
      description = ''
        Whether to manage this app.

        When false the app is ignored and what this module set for it is undone: Steam settings return to their defaults, a non-Steam app's shortcut is removed along with its artwork and play time, files placed under `files` are removed, and a patched or deleted file is put back as it was. Anything the game itself wrote is left alone.
      '';
    };

    compatTool = lib.mkOption {
      type = with types; nullOr (either str package);
      default = null;
      example = lib.literalExpression "pkgs.proton-ge-bin";
      description = ''
        Compatibility tool to use, either the internal name of an installed tool (e.g. `"proton_experimental"`), or a package containing one.
      '';
    };

    env = lib.mkOption {
      type =
        with types;
        lazyAttrsOf (
          nullOr (oneOf [
            str
            path
            int
            float
            bool
          ])
        );
      default = { };
      example = lib.literalExpression ''
        {
          DXVK_HUD = "fps,gpuload";
          PROTON_ENABLE_WAYLAND = 1;
          TZ = null;
        }
      '';
      description = ''
        Environment variables to export in the app's wrapper script, so they apply to this app rather than to Steam as a whole. Set a value to `null` to unset that variable.

        Setting this overwrites any launch options set by hand in Steam, because the module writes the launch options field itself. Move a string you want to keep into `rawLaunchOptions`.
      '';
    };

    wrappers = lib.mkOption {
      type = types.listOf (types.coercedTo types.package lib.getExe types.str);
      default = [ ];
      example = lib.literalExpression ''
        [
          (lib.getExe' pkgs.mangohud "mangohud")
          pkgs.gamescope
          "gamemoderun"
        ]
      '';
      description = ''
        Executables to wrap the game with.

        Setting this overwrites any launch options set by hand in Steam, because the module writes the launch options field itself. Move a string you want to keep into `rawLaunchOptions`.
      '';
    };

    args = lib.mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = lib.literalExpression ''
        [
          "-modded"
          "--launcher-skip"
          "-skipStartScreen"
        ]
      '';
      description = ''
        Arguments to pass to the game.

        Setting this overwrites any launch options set by hand in Steam, because the module writes the launch options field itself. Move a string you want to keep into `rawLaunchOptions`.
      '';
    };

    preHook = lib.mkOption {
      type = types.lines;
      default = "";
      example = ''
        if [[ "$*" == *"-force-vulkan"* ]]; then
          export PROTON_ENABLE_WAYLAND=1
        fi

        for i in "''${!game_command[@]}"; do
          game_command[i]="''${game_command[i]//\/Launcher.exe/\/game.exe}"
        done
      '';
      description = ''
        Extra bash code to run before executing the game.

        The variables from `env` are already exported at this point, and these arrays are in scope to read or modify:

        - `wrappers`
        - `game_command`: the `%command%` Steam passes in
        - `args`

        Setting this overwrites any launch options set by hand in Steam, because the module writes the launch options field itself. Move a string you want to keep into `rawLaunchOptions`.
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
      description = ''
        DLL overrides for the app, an attribute set mapping a DLL name to its load order.

        Each value is a `WINEDLLOVERRIDES` mode:

        - `"n"`: native
        - `"b"`: builtin
        - `"n,b"`: native, then builtin
        - `"b,n"`: builtin, then native
        - `"disabled"`: do not load the DLL

        These are compiled into the single `WINEDLLOVERRIDES` environment variable.

        Cannot be combined with setting `WINEDLLOVERRIDES` directly in `env`.

        Setting this overwrites any launch options set by hand in Steam, because the module writes the launch options field itself. Move a string you want to keep into `rawLaunchOptions`.
      '';
    };

    prefixPath = lib.mkOption {
      type = with types; nullOr (either str path);
      default =
        let
          fromEnv = config.env.STEAM_COMPAT_DATA_PATH or null;
        in
        if lib.isString fromEnv || lib.isPath fromEnv then fromEnv else null;
      defaultText = lib.literalMD "`env.STEAM_COMPAT_DATA_PATH` if it is set to a string or a path, otherwise `null`";
      example = "/mnt/games/prefixes/starfield";
      description = ''
        Directory to keep the app's Proton prefix in, instead of the default `steamapps/compatdata/<id>`.

        The directory is created on launch if its parent already exists, and `winetricks` follows it. The parent is never created, so a path on a drive that is not mounted yet fails instead of being written to the mount point.

        Setting this overwrites any launch options set by hand in Steam, because the module writes the launch options field itself. Move a string you want to keep into `rawLaunchOptions`.
      '';
    };

    rawLaunchOptions = lib.mkOption {
      type = types.nullOr types.singleLineStr;
      default = null;
      example = "gamemoderun %command%";
      description = ''
        Steam style launch options string, works exactly like in Steam:

        - Use `%command%` to mark where the game command runs.
        - A string with no `%command%` is appended to the game command as arguments.

        Usage of this option is discouraged in favour of `env`, `wrappers`, `args` and `preHook`, though it composes with them: the raw string is wrapped by `wrappers`, with `env` exported before it and `args` appended after.

        Setting this overwrites any launch options set by hand in Steam, because the module writes the launch options field itself.
      '';
    };

    winetricks = lib.mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [
        "vcrun2022"
        "corefonts"
      ];
      description = ''
        winetricks verbs to install into the app's Proton prefix.

        Applied when the app is launched (via protontricks, using the prefix and Proton that Steam provides in the environment), and re-applied when the verb list changes. The app must use a compatibility tool, and must have been launched once so the prefix exists.

        Removing a verb does not uninstall it, as winetricks cannot reliably undo verbs.

        Setting this overwrites any launch options set by hand in Steam, because the module writes the launch options field itself. Move a string you want to keep into `rawLaunchOptions`.
      '';
    };

    desktopEntry = {
      enable = lib.mkOption {
        type = types.bool;
        default = steamConfig.desktopEntries.enable;
        defaultText = lib.literalExpression "config.programs.steam.config.desktopEntries.enable";
        example = true;
        description = ''
          Whether to generate a desktop entry that launches this app through Steam.
        '';
      };

      name = lib.mkOption {
        type = types.str;
        default = config.name;
        defaultText = lib.literalExpression "config.name";
        example = "Cyberpunk 2077";
        description = "Name shown for the desktop entry.";
      };

      genericName = lib.mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "Role Playing Game";
        description = "Generic name for the desktop entry.";
      };

      comment = lib.mkOption {
        type = types.str;
        default = "Launch ${config.desktopEntry.name} with Steam";
        defaultText = lib.literalExpression ''"Launch ''${config.desktopEntry.name} with Steam"'';
        example = "Social VR, with mods";
        description = "Tooltip comment for the desktop entry.";
      };

      icon = lib.mkOption {
        type = with types; nullOr (either str path);
        default = "steam";
        defaultText = lib.literalMD ''the app's library icon when `desktopEntry.useLibraryIcon` is set, a non-Steam app's `artwork.icon` when it has one, otherwise `"steam"`'';
        example = lib.literalExpression "./icon.png";
        description = "Icon for the desktop entry, an icon name or image file.";
      };

      categories = lib.mkOption {
        type = types.listOf types.str;
        default = [ "Game" ];
        example = [
          "Game"
          "ActionGame"
        ];
        description = "Freedesktop categories for the desktop entry.";
      };
    };

    artwork =
      let
        mkArtworkOption =
          name: ext: text:
          lib.mkOption {
            type = types.nullOr types.path;
            default = null;
            example = lib.literalExpression "./${name}.${ext}";
            description = text;
          };
      in
      {
        cover = mkArtworkOption "cover" "jpg" "Portrait cover, 600x900, shown in the Steam library.";
        header = mkArtworkOption "header" "jpg" "Horizontal capsule, 460x215, shown in the Steam library.";
        hero = mkArtworkOption "hero" "jpg" "Wide banner shown behind the app page.";
        logo = mkArtworkOption "logo" "png" "Transparent title logo overlaid on the hero image.";
      };

    systemd = {
      enable = lib.mkOption {
        type = types.bool;
        default = false;
        example = true;
        description = ''
          Whether to publish a systemd user target that is active while the app is running.

          The app is launched in a transient scope, and that scope activates `steam-app-<name>.target`, along with a shared `steam-app.target` that is active while any app with `systemd.enable` set is running.

          To tie your own units to the app's lifetime, point their `PartOf` and `WantedBy` at the target, and their `Before` at it to make the app wait until they are up.

          Enabling this overwrites any launch options set by hand in Steam, because the module writes the launch options field itself. Move a string you want to keep into `rawLaunchOptions`.
        '';
      };

      target = {
        name = lib.mkOption {
          type = types.str;
          default = slugify config.name;
          defaultText = lib.literalMD "the app name, lowercased, with runs of other characters replaced by -";
          example = "vrchat";
          description = ''
            Name of the generated target, used as `steam-app-<name>.target`.

            Other configuration refers to this name, so changing it stops units that hook the old name from starting.
          '';
        };

        unitConfig = lib.mkOption {
          type = types.attrsOf (
            types.oneOf [
              types.str
              types.int
              types.bool
              (types.listOf types.str)
            ]
          );
          default = { };
          example = {
            Description = "VRChat";
          };
          description = ''
            Settings for the `[Unit]` section of the generated target, merged over the ones it sets itself.

            The generated target sets `Description`, `Documentation`, `StopWhenUnneeded`, `RefuseManualStart`, `RefuseManualStop`, and its dependencies on `steam-app.target`. Overriding `StopWhenUnneeded` or those dependencies stops the target being torn down when the app exits.
          '';
        };

        unitName = lib.mkOption {
          type = types.str;
          default = "steam-app-${config.systemd.target.name}.target";
          defaultText = lib.literalExpression ''"steam-app-''${config.systemd.target.name}.target"'';
          readOnly = true;
          description = "Unit name of the generated target.";
        };
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
        };
        description = ''
          Properties set on the transient scope the app runs in, passed to `systemd-run --property`.

          These cover:

          - resource control, such as `Slice`, `CPUWeight`, `MemoryMax` and `AllowedCPUs`
          - `OnSuccess`, to activate a unit once the app exits

          `OnFailure` is never triggered, because a scope's result does not follow the exit status of the processes inside it.

          Dependencies that tie other units to the app's lifetime belong on the target instead.
        '';
      };
    };

    steamRunId = lib.mkOption {
      type = types.str;
      default = toString config.id;
      defaultText = lib.literalExpression "toString config.id";
      description = ''
        Identifier passed to `steam://rungameid/`, for launching the app from outside Steam.

        - Steam apps use their app id
        - non-Steam apps use a 64 bit id derived from their app id
      '';
    };

    finalConfig = lib.mkOption {
      type = types.attrs;
      visible = false;
      internal = true;
    };
  };

  config.env = lib.mkIf (config.dllOverrides != { }) {
    WINEDLLOVERRIDES = lib.mkDefault (mkDllOverrides config.dllOverrides);
  };

  config.warnings =
    let
      rawSets = var: config.rawLaunchOptions != null && lib.hasInfix "${var}=" config.rawLaunchOptions;
    in
    lib.optional (rawSets "STEAM_COMPAT_DATA_PATH") "steam-config-nix: ${name} sets STEAM_COMPAT_DATA_PATH in rawLaunchOptions, which prefix aware options such as winetricks and files.prefix cannot follow, set prefixPath instead"
    ++ lib.optional (rawSets "WINEDLLOVERRIDES") "steam-config-nix: ${name} sets WINEDLLOVERRIDES in rawLaunchOptions, which overrides the compiled dllOverrides at launch, set dllOverrides instead";

  config.assertions =
    lib.optional
      (config.dllOverrides != { } && config.env.WINEDLLOVERRIDES != mkDllOverrides config.dllOverrides)
      {
        assertion = false;
        message = "steam-config-nix: ${name} sets both dllOverrides and env.WINEDLLOVERRIDES, set overrides via dllOverrides only";
      }
    ++
      lib.optional
        (config.systemd.enable && lib.match "[A-Za-z0-9:_.-]+" config.systemd.target.name == null)
        {
          assertion = false;
          message = "steam-config-nix: ${name} has an invalid systemd.target.name \"${config.systemd.target.name}\", use letters, digits, and any of :_.-";
        };

  config.finalConfig = {
    inherit (config)
      id
      compatTool
      ;
    prefixPath = if config.prefixPath == null then null else toString config.prefixPath;
    launchOptions = config.wrapper.exec;
    artwork = {
      inherit (config.artwork)
        cover
        header
        hero
        logo
        ;
    };
  };
}
