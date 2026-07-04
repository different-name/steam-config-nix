{
  lib,
  pkgs,
  dataDir,
}:
{ name, config, ... }:
let
  inherit (lib) types;

  # modified from home-manager lib.shell.exportAll
  # https://github.com/nix-community/home-manager/blob/89c9508bbe9b40d36b3dc206c2483ef176f15173/modules/lib/shell.nix#L36-L42
  exportUnset = n: v: if v == null then "unset ${n}" else ''export ${n}="${toString v}"'';
  exportAll = lib.concatMapAttrsStringSep "\n" exportUnset;

  mkAppWrapperPackage =
    app:
    let
      hasOptions = app.hasLaunchOptions;
      hasStrOptions = app.launchOptionsStr != null;

      # for nix style launch options
      script = ''
        ${exportAll app.launchOptions.env}

        declare -a wrappers=(${lib.escapeShellArgs app.launchOptions.wrappers})
        declare -a game_command=("$@")
        declare -a args=(${lib.escapeShellArgs app.launchOptions.args})

        ${app.launchOptions.preHook}

          exec env "''${wrappers[@]}" "''${game_command[@]}" "''${args[@]}"
      '';

      # for traditional single line string launch options
      strScript = "exec env ${lib.replaceString "%command%" ''"$@"'' app.launchOptionsStr}";

      package = pkgs.writeShellScriptBin "steam-app-wrapper-${toString app.id}" (
        if hasStrOptions then strScript else script
      );
    in
    if hasOptions || hasStrOptions then package else null;

  launchOptionsOptions = {
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
        Environment variables to export in the launch script.
        You can also unset variables by setting their value to `null`.
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
  };
in
{
  imports = lib.singleton (
    lib.mkRenamedOptionModule [ "launchOptions" "extraConfig" ] [ "launchOptions" "preHook" ]
  );

  options = {
    compatTool = lib.mkOption {
      type = with types; nullOr (either str package);
      default = null;
      example = lib.literalExpression "pkgs.proton-ge-bin";
      description = ''
        Compatibility tool to use, either the internal name of an installed
        tool (e.g. `"proton_experimental"`), or a package containing one.

        Packages are installed automatically, see the readme for details.
      '';
    };

    launchOptions = launchOptionsOptions;

    launchOptionsStr = lib.mkOption {
      type = types.nullOr types.singleLineStr;
      default = null;
      description = ''
        Traditional Steam launch options.

        Cannot be combined with `launchOptions`.
      '';
    };

    desktopEntry = {
      enable = lib.mkEnableOption "a desktop entry that launches this app through Steam";

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

    steamRunId = lib.mkOption {
      type = types.str;
      default = toString config.id;
      defaultText = lib.literalExpression "toString config.id";
      visible = false;
      internal = true;
      description = "Identifier passed to `steam://rungameid/`.";
    };

    hasLaunchOptions = lib.mkOption {
      type = types.bool;
      default =
        config.launchOptions.env != { }
        || config.launchOptions.wrappers != [ ]
        || config.launchOptions.args != [ ]
        || config.launchOptions.preHook != "";
      visible = false;
      internal = true;
      readOnly = true;
    };

    dataDir = lib.mkOption {
      default = "${dataDir}/apps/${toString config.id}";
      visible = false;
      internal = true;
      readOnly = true;
    };

    wrapper = lib.mkOption {
      default =
        let
          package = mkAppWrapperPackage config;
          path = if package == null then null else "${config.dataDir}/wrapper";
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
  };
}
