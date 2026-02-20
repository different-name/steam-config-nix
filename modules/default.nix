self: format:
{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib) types;
  inherit (import ../lib.nix lib) exportAll;

  dataHome =
    if format == "nixos" then
      "/var/lib"
    else if format == "home-manager" then
      config.xdg.dataHome
    else
      throw "unexpected format, must be one of: nixos, home-manager";
in
{
  imports = lib.singleton (
    lib.mkRemovedOptionModule
      [
        "programs"
        "steam"
        "config"
        "users"
      ]
      ''
        Please use global app configuration instead.
        See https://github.com/different-name/steam-config-nix/discussions/33
      ''
  );

  options.programs.steam.config =
    let
      dataDir = "${dataHome}/steam-config-nix";

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
      enable = lib.mkEnableOption "declarative Steam configuration";

      package = lib.mkOption {
        type = types.package;
        default = self.packages.${pkgs.stdenv.hostPlatform.system}.steam-config-patcher;
        description = "The steam-config-patcher package to use.";
      };

      closeSteam = lib.mkEnableOption "automatic Steam shutdown before writing configuration changes";

      defaultCompatTool = lib.mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "proton_experimental";
        description = ''
          Default compatibility tool to use for Steam Play.

          This option sets the default compatibility tool in Steam, but does not set the nix module defaults.
        '';
      };

      apps = lib.mkOption {
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

                compatTool = lib.mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  example = "proton_experimental";
                  description = "Compatibility tool to use.";
                };

                launchOptions = lib.mkOption {
                  type =
                    with types;
                    nullOr (oneOf [
                      package
                      launchOptionsSubmodule
                      singleLineStr
                    ]);

                  default = null;

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

                        for i in "''${!game_command[@]}"; do
                          game_command[i]="''${game_command[i]//\/Launcher.exe/\/game.exe}"
                        done
                      ''';
                    };'';

                  apply =
                    value:
                    if lib.isDerivation value then
                      throw ''
                        steam-config-nix: launchOptions no longer supports derivations.
                        Migrate to the launchOptions.extraConfig option, which will allows for the same flexibility.
                        See https://github.com/different-name/steam-config-nix/discussions/34
                      ''
                    else if lib.typeOf value == "string" then
                      throw "steam-config-nix: launchOptions no longer supports string values, use launchOptionsStr instead."
                    else
                      value;
                };

                launchOptionsStr = lib.mkOption {
                  type = types.nullOr types.singleLineStr;
                  default = null;
                  description = ''
                    Traditional Steam launch options.
                                      
                    If this is defined it will be used instead of the `launchOption` option.
                  '';
                };

                wrapperPath = lib.mkOption {
                  visible = false;
                  internal = true;
                  readOnly = true;
                  default =
                    if config.launchOptions != null then "${dataDir}/app-wrappers/${toString config.id}" else null;
                };
              };
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
      };
    };

  config =
    let
      cfg = config.programs.steam.config;

      mkLaunchOptionsWrapper =
        app:
        pkgs.writeShellScriptBin "steam-app-wrapper-${toString app.id}" (
          if app.launchOptionsStr == null then
            ''
              ${exportAll app.launchOptions.env}

              declare -a wrappers=(${lib.escapeShellArgs app.launchOptions.wrappers})
              declare -a game_command=("$@")
              declare -a args=(${lib.escapeShellArgs app.launchOptions.args})

              ${app.launchOptions.preHook}

              exec env "''${wrappers[@]}" "''${game_command[@]}" "''${args[@]}"
            ''
          else
            "exec env ${lib.replaceString "%command%" ''"$@"'' app.launchOptionsStr}"
        );

      launchOptionApps = lib.filter (app: app.launchOptions != null) (lib.attrValues cfg.apps);
      launchOptionLinks = map (app: {
        target = app.wrapperPath;
        source = lib.getExe (mkLaunchOptionsWrapper app);
      }) launchOptionApps;

      patcherConfig = builtins.toJSON {
        inherit (cfg) closeSteam defaultCompatTool;
        apps = lib.mapAttrs (_: app: {
          inherit (app) id compatTool;
          launchOptions = if app.wrapperPath == null then null else "${app.wrapperPath} %command%";
        }) cfg.apps;
      };

      service = {
        description = "Steam config patcher script";
        restartTriggers = [ (lib.hashString "md5" patcherConfig) ];

        config = {
          Type = "oneshot";
          RemainAfterExit = true; # allows service to be restarted by restartTriggers
          ExecStart = lib.escapeShellArgs [
            (lib.getExe cfg.package)
            (pkgs.writeText "steam-config-patcher-cfg" patcherConfig)
          ];
        };
      };
    in
    lib.mkIf cfg.enable (
      lib.mkMerge [
        (lib.optionalAttrs (format == "nixos") {
          systemd.tmpfiles.rules = map (
            link: "L+ ${lib.escapeShellArg link.target} - - - - ${lib.escapeShellArg link.source}"
          ) launchOptionLinks;

          # system service instead of a user service due to https://github.com/NixOS/nixpkgs/issues/246611
          # nixos user services also don't restart on rebuild, requiring a user activation script
          systemd.services."steam-config-patcher@" = {
            inherit (service) description restartTriggers;

            serviceConfig = service.config // {
              User = "%i";
              Group = "users";
            };
          };

          systemd.targets.multi-user.wants =
            let
              normalUsers = lib.filter (user: user.isNormalUser) (lib.attrValues (config.users.users));
            in
            map (user: "steam-config-patcher@${user.name}.service") normalUsers;
        })

        (lib.optionalAttrs (format == "home-manager") {
          home.file = lib.listToAttrs (
            map (link: lib.nameValuePair link.target { inherit (link) source; }) launchOptionLinks
          );

          systemd.user.services."steam-config-patcher" = {
            Unit = {
              Description = service.description;
              X-Restart-Triggers = service.restartTriggers;
            };

            Service = service.config;
            Install.WantedBy = [ "default.target" ];
          };
        })
      ]
    );
}
