{
  lib,
  pkgs,
  dataDir,
}:
{ config, ... }:
let
  inherit (lib) types;

  # modified from home-manager lib.shell.exportAll
  # https://github.com/nix-community/home-manager/blob/89c9508bbe9b40d36b3dc206c2483ef176f15173/modules/lib/shell.nix#L36-L42
  exportUnset = n: v: if v == null then "unset ${n}" else ''export ${n}="${toString v}"'';
  exportAll = lib.concatMapAttrsStringSep "\n" exportUnset;

  mkAppWrapperPackage =
    app:
    let
      hasOptions = app.launchOptions != null;
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

  launchOptionsSubmodule = types.submodule {
    imports = lib.singleton (lib.mkRenamedOptionModule [ "extraConfig" ] [ "preHook" ]);

    options = {
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
  };
in
{
  options = {
    compatTool = lib.mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "proton_experimental";
      description = "Compatibility tool to use.";
    };

    /*
      this is currently an option that accept the launchOptions submodule, a package or a singleLineStr
      this is only to provide informational error messages for those who have not migrated to the new options
      this should be removed after a while and the launchOptions options should be declared directly, instead of through a submodule
    */
    launchOptions = lib.mkOption {
      type =
        with types;
        nullOr (oneOf [
          launchOptionsSubmodule
          singleLineStr # use the launchOptionsStr option instead
          package # packages are no longer supported
        ]);

      default = null;

      apply =
        value:
        if lib.isDerivation value then
          throw ''
            steam-config-nix: launchOptions no longer supports derivations.
            Migrate to the launchOptions.preHook option, which will allows for the same flexibility.
            See https://github.com/different-name/steam-config-nix/discussions/34
          ''
        else if lib.typeOf value == "string" then
          throw "steam-config-nix: launchOptions no longer supports string values, use launchOptionsStr instead."
        else
          value;

      description = ''
        App launch options, see example for usage.

        If `launchOptionsStr` is defined, that will be used instead.
      '';

      example = lib.literalExpression ''
        {
          # Environment variables
          env = {
            PROTON_USE_NTSYNC = true;
            TZ = null; # This unsets the variable
          };

          # Arguments for the game's executable (%command% <...>)
          args = [
            "-force-vulkan"
          ];

          # Programs to wrap the game with (<...> %command%)
          wrappers = [
            (lib.getExe pkgs.gamemode)
            "mangohud"
          ];

          /*
            Extra bash code to run before executing the game
            These variables are available in scope for you to read / modify in this hook:
              `wrappers`: values from the wrappers option
              `game_command`: the %command% passed from steam
              `args`: values from the args option
          */
          preHook = '''
            if [[ "$*" == *"-force-vulkan"* ]]; then
              export PROTON_ENABLE_WAYLAND=1
            fi

            for i in "'''''${!game_command[@]}"; do
              game_command[i]="'''''${game_command[i]//\/Launcher.exe/\/game.exe}"
            done
          ''';
        };'';
    };

    launchOptionsStr = lib.mkOption {
      type = types.nullOr types.singleLineStr;
      default = null;
      description = ''
        Traditional Steam launch options.
                          
        If this is defined it will be used instead of the `launchOption` option.
      '';
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
