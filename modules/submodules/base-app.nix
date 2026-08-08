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

  # modified from home-manager lib.shell.exportAll
  # https://github.com/nix-community/home-manager/blob/89c9508bbe9b40d36b3dc206c2483ef176f15173/modules/lib/shell.nix#L36-L42
  exportUnset = n: v: if v == null then "unset ${n}" else ''export ${n}="${toString v}"'';
  exportAll = lib.concatMapAttrsStringSep "\n" exportUnset;

  # Steam's launch runtime sets LD_LIBRARY_PATH/LD_PRELOAD to libs that clash
  # with notify-send, so run it with a clean loader environment
  notify =
    body:
    lib.optionalString steamConfig.notifications ''( unset LD_LIBRARY_PATH LD_PRELOAD; ${lib.getExe' pkgs.libnotify "notify-send"} -a steam-config-nix "steam-config-nix" "${body}" ) >/dev/null 2>&1 || true'';

  mkAppWrapperPackage =
    app:
    let
      hasOptions = app.env != { } || app.wrappers != [ ] || app.args != [ ] || app.preHook != "";
      hasRaw = app.rawLaunchOptions != null;
      hasWinetricks = app.winetricks != [ ];

      # runs before the game, when Steam has set STEAM_COMPAT_* in the environment
      # marker keyed on the verb list so it only runs when the verbs change
      winetricksStep = lib.optionalString hasWinetricks ''
        if [ -n "''${STEAM_COMPAT_DATA_PATH:-}" ] && [ -d "$STEAM_COMPAT_DATA_PATH/pfx" ]; then
          marker="$STEAM_COMPAT_DATA_PATH/steam-config-nix-winetricks"
          want=${lib.escapeShellArg (lib.concatStringsSep " " app.winetricks)}
          if [ "$(cat "$marker" 2>/dev/null)" != "$want" ]; then
            echo "steam-config-nix: applying winetricks verbs: $want"
            ${notify "Installing winetricks: $want…"}
            if ${lib.getExe' pkgs.protontricks "protontricks"} "''${STEAM_COMPAT_APP_ID}" -q ${lib.escapeShellArgs app.winetricks}; then
              printf '%s' "$want" > "$marker"
              ${notify "winetricks installed: $want"}
            else
              echo "steam-config-nix: winetricks failed, continuing to launch" >&2
              ${notify "winetricks failed for app ${toString app.id}"}
            fi
          fi
        fi
      '';

      # steam appends a launch string with no %command% as args to the game
      effectiveRaw =
        if !hasRaw then
          null
        else if lib.hasInfix "%command%" app.rawLaunchOptions then
          app.rawLaunchOptions
        else
          "%command% ${app.rawLaunchOptions}";

      # env applies the raw string's leading VAR=val assignments
      gameInvocation =
        if hasRaw then
          "env ${lib.replaceString "%command%" ''"''${game_command[@]}"'' effectiveRaw}"
        else
          ''"''${game_command[@]}"'';

      launchStep =
        if hasOptions then
          ''
            # Steam configuration for ${name}

            ${exportAll app.env}

            declare -a wrappers=(${lib.escapeShellArgs app.wrappers})
            declare -a game_command=("$@")
            declare -a args=(${lib.escapeShellArgs app.args})

            ${app.preHook}

            exec env "''${wrappers[@]}" ${gameInvocation} "''${args[@]}"
          ''
        else if hasRaw then
          "exec env ${lib.replaceString "%command%" ''"$@"'' effectiveRaw}"
        else
          ''exec "$@"'';

      package = pkgs.writeShellScriptBin "steam-app-wrapper-${toString app.id}" ''
        ${winetricksStep}
        ${launchStep}
      '';
    in
    if hasOptions || hasRaw || hasWinetricks then package else null;

in
{
  imports = [
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
        default = if config.artwork.icon != null then config.artwork.icon else "steam";
        defaultText = lib.literalExpression ''the app's artwork.icon, or "steam"'';
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

    steamRunId = lib.mkOption {
      type = types.str;
      default = toString config.id;
      defaultText = lib.literalExpression "toString config.id";
      visible = false;
      internal = true;
      description = "Identifier passed to `steam://rungameid/`.";
    };

    wrapper = lib.mkOption {
      default =
        let
          package = mkAppWrapperPackage config;
          path = if package == null then null else "${dataDir}/apps/${toString config.id}/wrapper";
          exec = if package == null then null else "${path} %command%";
        in
        {
          inherit
            package # wrapper derivation
            path # path to in-home symlink of wrapper
            exec # the string provided to steam to launch the app
            ;
        };
      visible = false;
      internal = true;
      readOnly = true;
    };

    finalConfig = lib.mkOption {
      type = types.attrs;
      visible = false;
      internal = true;
    };
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
