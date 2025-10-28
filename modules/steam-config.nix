{
  lib,
  config,
  inputs,
  pkgs,
  ...
}:
let
  inherit (lib) types;
  inherit (lib.hm.shell) exportAll;
  nestedAttrsOfStrings = types.lazyAttrsOf (types.either types.str nestedAttrsOfStrings);

  cfg = config.programs.steam.config;

  dataDir = "${config.xdg.dataHome}/steam-config-nix";

  makeWrapperPath =
    userId: appId:
    let
      userDir = lib.replaceString "*" "shared" (toSteamId3 userId);
    in
    "${dataDir}/users/${userDir}/app-wrappers/${appId}";

  # Get a Steam3ID from a Steam64ID
  # https://gist.github.com/bcahue/4eae86ae1d10364bb66d
  toSteamId3 =
    userId:
    let
      steamId64Ident = 76561197960265728;
      userIdInt = lib.strings.toIntBase10 userId;
      isSteam64 = userId != "*" && userIdInt >= steamId64Ident;
    in
    if isSteam64 then toString (userIdInt - steamId64Ident) else userId;

  writeWrapperBin = appId: text: pkgs.writeShellScriptBin "app-${appId}-wrapped" text;
  writeLaunchOptionsBin =
    appId: launchOptions:
    let
      launchCommand =
        if lib.strings.hasInfix "%command%" launchOptions then
          lib.replaceString "%command%" ''"$@"'' launchOptions
        else
          ''"$@" ${launchOptions}'';
    in
    writeWrapperBin appId "exec env ${launchCommand}";

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
        description = ''
          Executables to wrap the game with.
        '';
      };
      args = lib.mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = lib.literalExpression ''
          ["-modded" "--launcher-skip" "-skipStartScreen"]
        '';
        description = ''
          CLI arguments to pass to the game.
        '';
      };
      extraConfig = lib.mkOption {
        type = types.lines;
        default = "";
        example = ''
          if [[ "$*" != *"--no-vr"* ]]; then
            export PROTON_ENABLE_WAYLAND=1
          fi
        '';
        description = ''
          Additional bash code to execute before the game.
        '';
      };
    };
  };

  mkSteamAppsOption =
    {
      launchOptions ? false,
      compatTool ? false,
    }:
    lib.mkOption {
      type = types.attrsOf (
        types.submodule (
          { config, name, ... }:
          {
            options = lib.mergeAttrsList [
              (lib.optionalAttrs launchOptions {
                launchOptions = lib.mkOption {
                  type =
                    with types;
                    nullOr (oneOf [
                      package
                      launchOptionsSubmodule
                      (coercedTo singleLineStr (writeLaunchOptionsBin name) package)
                    ]);
                  default = null;
                  example = "-vulkan";
                  description = "Game launch options";
                };

                finalScript = lib.mkOption {
                  type = types.nullOr types.package;
                  visible = false;
                  default = config.launchOptions;
                  description = "The final script the game will run on launch";
                };
              })

              (lib.optionalAttrs compatTool {
                compatTool = lib.mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  example = "proton_experimental";
                  description = "Compatibility tool to use, referenced by display name";
                };
              })
            ];

            config = lib.mkIf launchOptions {
              finalScript = lib.mkIf (!lib.isDerivation config.launchOptions) (
                lib.mkDefault (
                  let
                    prefix = lib.escapeShellArgs config.launchOptions.wrappers;
                    suffix = lib.escapeShellArgs config.launchOptions.args;
                  in
                  writeWrapperBin name ''
                    ${exportAll config.launchOptions.env}

                    ${config.launchOptions.extraConfig}

                    exec env ${prefix} "$@" ${suffix}
                  ''
                )
              );
            };
          }
        )
      );

      default = { };
      description = ''
        Configuration for a Steam app
        App IDs can be found through https://steamdb.info/ or through the game's store page URL
      '';
    };
in
{
  imports = [
    (lib.mkRemovedOptionModule [ "programs" "steam" "localconfig" ] ''
      programs.steam.localconfig has been removed in favor of programs.steam.config
      See the steam-config-nix readme for new usage instructions
    '')
  ];

  options.programs.steam.config = {
    enable = lib.mkEnableOption "Steam user config store management";

    package = lib.mkOption {
      default = inputs.self.packages.${pkgs.system}.steam-config-patcher;
      description = ''
        The steam-config-patcher package to use.
      '';
      type = types.package;
    };

    steamDir = lib.mkOption {
      type = types.path;
      default = "${config.home.homeDirectory}/.steam/steam";
      description = ''
        Path to the Steam directory 
      '';
    };

    closeSteam = lib.mkEnableOption "automatic closing of Steam when writing configuration changes";

    apps = mkSteamAppsOption {
      launchOptions = true;
      compatTool = true;
    };

    users = lib.mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            apps = mkSteamAppsOption { launchOptions = true; };
          };
        }
      );
      default = { };
      description = ''
        Per user configuration for a Steam app
        User IDs are in SteamID64 format, for example 98765432123456789
        You can find your SteamID64 through https://steamid.io/lookup
      '';
    };

    finalConfig = lib.mkOption {
      type = nestedAttrsOfStrings;
      visible = false;
      default = { };
    };
  };

  config = lib.mkIf cfg.enable {
    programs.steam.config = {
      users."*".apps = lib.mapAttrs (_: app: { inherit (app) launchOptions; }) cfg.apps;

      finalConfig = lib.mkMerge [
        (
          let
            compatToolConfigs = lib.filterAttrs (_: app: app.compatTool != null) cfg.apps;
          in
          lib.mkIf (compatToolConfigs != { }) {
            "${cfg.steamDir}/config/config.vdf" = {
              InstallConfigStore.Software.Valve.Steam = {
                CompatToolMapping = lib.mapAttrs (_: app: {
                  name = app.compatTool;
                  config = "";
                  priority = "250";
                }) compatToolConfigs;
              };
            };
          }
        )

        (lib.mapAttrs' (
          userId: user:
          let
            steamID = toSteamId3 userId;
          in
          {
            name = "${cfg.steamDir}/userdata/${steamID}/config/localconfig.vdf";
            value = {
              UserLocalConfigStore.Software.Valve.Steam.Apps = lib.mapAttrs (appId: app: {
                LaunchOptions = "${config.xdg.dataHome}/${makeWrapperPath steamID appId} %command%";
              }) user.apps;
            };
          }
        ) cfg.users)
      ];
    };

    home.file = lib.listToAttrs (
      lib.flatten (
        lib.mapAttrsToList (
          userId: user:
          lib.mapAttrsToList (appId: app: {
            name = makeWrapperPath (toSteamId3 userId) appId;
            value.source = lib.getExe app.finalScript;
          }) (lib.filterAttrs (_: app: app.finalScript != null) user.apps)
        ) cfg.users
      )
    );

    home.activation.steam-config-patcher =
      let
        arguments = lib.cli.toGNUCommandLineShell { } {
          json = builtins.toJSON config.programs.steam.config.finalConfig;
          close-steam = cfg.closeSteam;
        };
      in
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${lib.getExe cfg.package} ${arguments}
      '';
  };
}
