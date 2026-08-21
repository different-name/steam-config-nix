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
  baseAppWrapperModule = import ./base-app-wrapper.nix { inherit lib pkgs dataDir; };

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

        When false the app is ignored, and any configuration previously applied for it is reverted.
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
          WINEDLLOVERRIDES = "winmm,version=n,b";
          TZ = null;
        }
      '';
      description = ''
        Environment variables to export in the launch script. You can also unset variables by setting their value to `null`.
      '';
    };

    wrappers = lib.mkOption {
      type = types.listOf (types.coercedTo types.package lib.getExe types.str);
      default = [ ];
      example = lib.literalExpression ''
        [
          (lib.getExe' pkgs.mangohud "mangohud")
          pkgs.myWrapperProgram
          "gamemoderun"
        ]
      '';
      description = "Executables to wrap the game with.";
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
      description = "Arguments to pass to the game.";
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
        Extra bash code to run before executing the game

        These variables are available in scope for you to read / modify in this hook:

         - `wrappers`: values from the wrappers option
         - `game_command`: the %command% passed from steam
         - `args`: values from the args option
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

        Each value is a `WINEDLLOVERRIDES` mode: `"n"` (native), `"b"` (builtin), `"n,b"` (native then builtin), `"b,n"` (builtin then native), or `"disabled"`. These are compiled into the single `WINEDLLOVERRIDES` environment variable, so mods and other presets can contribute overrides without clobbering each other.

        Cannot be combined with setting `WINEDLLOVERRIDES` directly in `env`.
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

        Usage of this option is discouraged in favor of the structured launch options, however this option is compatible with them. Wrapped by `wrappers` with `env` and `args` applied around it.
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

        Setting this will overwrite any launch options set manually in Steam.
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
        default = name;
        defaultText = lib.literalExpression "<name>";
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
        description = "Tooltip comment for the desktop entry.";
      };

      icon = lib.mkOption {
        type = with types; nullOr (either str path);
        default = "steam";
        example = lib.literalExpression "./icon.png";
        description = "Icon for the desktop entry, an icon name or image file.";
      };

      categories = lib.mkOption {
        type = types.listOf types.str;
        default = [ "Game" ];
        description = "Freedesktop categories for the desktop entry.";
      };
    };

    artwork =
      let
        mkArtworkOption =
          description: dimensions:
          lib.mkOption {
            type = types.nullOr types.path;
            default = null;
            example = lib.literalExpression "./${description}.jpg";
            description = "${description} (${dimensions}) shown in the Steam library.";
          };
      in
      {
        cover = mkArtworkOption "cover" "600x900 portrait";
        header = mkArtworkOption "header" "460x215 horizontal";
        hero = mkArtworkOption "hero" "background";
        logo = mkArtworkOption "logo" "transparent overlay";
      };

    systemd = {
      enable = lib.mkOption {
        type = types.bool;
        default = false;
        example = true;
        description = ''
          Whether to publish a systemd user target that is active while the app is running.

          The app is launched in a transient scope, and that scope activates `steam-app-<name>.target` along with the shared `steam-app.target`. Units are tied to the app's lifetime by setting `PartOf` and `WantedBy` on them, and `Before` to make the app wait until they are up.

          Enabling this will overwrite any launch options set manually in Steam.
        '';
      };

      target = {
        name = lib.mkOption {
          type = types.str;
          default = slugify name;
          defaultText = lib.literalMD "the attribute name, lowercased, with runs of other characters replaced by `-`";
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
          description = "Unit name of the generated target, for referring to it without repeating the string.";
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
        - non-Steam apps use a 64 bit id derived from theirs, which is a different number
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
      id # option must be defined by module importing base app
      compatTool
      ;
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
