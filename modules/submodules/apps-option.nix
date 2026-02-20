{
  dataDir,
  rootOptionPath ? [ ],
  userId,
  supportCompatTool,
}:
{ lib, pkgs, ... }:
let
  inherit (lib) types;
  inherit (import ../lib.nix lib) exportAll;

  appsOptionPath = rootOptionPath ++ [ "apps" ];

  writeWrapperBin = appId: text: pkgs.writeShellScriptBin "steam-app-wrapper-${toString appId}" text;

  writeLaunchOptionsStrBin =
    appId: launchOptions:
    let
      launchCommand =
        if lib.strings.hasInfix "%command%" launchOptions then
          lib.replaceString "%command%" ''"$@"'' launchOptions
        else
          ''"$@" ${launchOptions}'';
    in
    writeWrapperBin appId "exec env ${launchCommand}";

  writeLaunchOptionsSetBin =
    appId: launchOptionsSet:
    let
      inherit (launchOptionsSet) env wrappers args;
    in
    writeWrapperBin appId ''
      ${exportAll env}

      declare -a wrappers=(${lib.escapeShellArgs wrappers})
      declare -a game_command=("$@")
      declare -a args=(${lib.escapeShellArgs args})

      ${launchOptionsSet.extraConfig}

      exec env "''${wrappers[@]}" "''${game_command[@]}" "''${args[@]}"
    '';

  launchOptionsSubmodule = types.submodule {
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
            "TZ" = null;
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

              # Need to enable gamemode module in NixOS
              "gamemoderun"
            ]
        '';
        description = "Executables to wrap the game with.";
      };
      args = lib.mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = lib.literalExpression ''
          ["-modded" "--launcher-skip" "-skipStartScreen"]
        '';
        description = "CLI arguments to pass to the game.";
      };
      extraConfig = lib.mkOption {
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
  options = lib.setAttrByPath appsOptionPath (
    lib.mkOption {
      type = types.attrsOf (
        types.submodule (
          { name, config, ... }:
          {
            options = {
              id = lib.mkOption {
                type = types.int;
                default = lib.strings.toIntBase10 name;
                defaultText = lib.literalExpression "lib.strings.toIntBase10 <name>";
                example = 438100;
                description = ''
                  The Steam App ID.

                  App IDs can be found through the game's store page URL.

                  If an ID is not provided, the app's `<name>` will be used.
                '';
              };

              launchOptions = lib.mkOption {
                type =
                  with types;
                  nullOr (oneOf [
                    package
                    launchOptionsSubmodule
                    (coercedTo singleLineStr (writeLaunchOptionsStrBin config.id) package)
                  ]);
                default = null;
                description = ''
                  The Launch options to use.

                  Launch options can be provided as either:

                  **`singleLineStr`**

                  ```nix
                  '''env -u TZ PRESSURE_VESSEL_FILESYSTEMS_RW="$XDG_RUNTIME_DIR/wivrn/comp_ipc" %command% --use-d3d11'''
                  ```

                  **`launchOptionsSubmodule`**

                  ```nix
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
                    extraConfig = '''
                      if [[ "$*" == *"-force-vulkan"* ]]; then
                        export PROTON_ENABLE_WAYLAND=1
                      fi

                      for i in "''${!game_command[@]}"; do
                        game_command[i]="''${game_command[i]//\/Launcher.exe/\/game.exe}"
                      done
                    ''';
                  };
                  ```'';
                example = lib.literalExpression ''
                  {
                    env.WINEDLLOVERRIDES = "winmm,version=n,b";
                    args = [
                      "--launcher-skip"
                      "-skipStartScreen"
                    ];
                  }'';
                apply =
                  value:
                  if (lib.isDerivation value) || value == null then
                    value
                  else
                    writeLaunchOptionsSetBin config.id value;
              };

              wrapperPath = lib.mkOption {
                type = types.nullOr types.path;
                visible = false;
                default =
                  if config.launchOptions != null then
                    "${dataDir}/users/${toString userId}/app-wrappers/${toString config.id}"
                  else
                    null;
              };
            }
            // (lib.optionalAttrs supportCompatTool {
              compatTool = lib.mkOption {
                type = types.nullOr types.str;
                default = null;
                example = "proton_experimental";
                description = "Compatibility tool to use.";
              };
            });
          }
        )
      );

      default = { };
      example = lib.literalExpression ''
        {
          # App IDs can be provided through the `id` property
          spin-rhythm = {
            id = 1058830;
            launchOptions = "DVXK_ASYNC=1 gamemoderun %command%";
          };

          # Or be provided through the `<name>`
          "620".launchOptions = "-vulkan";
        }'';
      description = "Configuration per Steam app.";
    }
  );
}
