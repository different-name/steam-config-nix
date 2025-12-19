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
    userId: appId: "${dataDir}/users/${toString userId}/app-wrappers/${toString appId}";

  # Get a SteamID3 from a SteamID64
  # https://gist.github.com/bcahue/4eae86ae1d10364bb66d
  toSteamId3 =
    userId:
    let
      steamId64Ident = 76561197960265728;
      isSteam64 = userId >= steamId64Ident;
    in
    if isSteam64 then toString (userId - steamId64Ident) else userId;

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
      prefix = lib.escapeShellArgs launchOptionsSet.wrappers;
      suffix = lib.escapeShellArgs launchOptionsSet.args;
    in
    writeWrapperBin appId ''
      ${exportAll launchOptionsSet.env}
      ${launchOptionsSet.extraConfig}
      exec env ${prefix} "$@" ${suffix}
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
          if [[ "$*" != *"--no-vr"* ]]; then
            export PROTON_ENABLE_WAYLAND=1
          fi
        '';
        description = "Additional bash code to execute before the game.";
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
              {
                id = lib.mkOption {
                  type = types.int;
                  default = lib.strings.toIntBase10 name;
                  example = 438100;
                  description = ''
                    The ID for this app.
                    App IDs can be found through https://steamdb.info/ or through the game's store page URL.
                  '';
                };
              }

              (lib.optionalAttrs launchOptions {
                launchOptions = lib.mkOption {
                  type =
                    with types;
                    nullOr (oneOf [
                      package
                      launchOptionsSubmodule
                      (coercedTo singleLineStr (writeLaunchOptionsStrBin config.id) package)
                    ]);
                  default = null;
                  example = "-vulkan";
                  description = "Game launch options";
                  apply =
                    value:
                    if (lib.isDerivation value) || value == null then
                      value
                    else
                      writeLaunchOptionsSetBin config.id value;
                };
              })

              (lib.optionalAttrs compatTool {
                compatTool = lib.mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  example = "proton_experimental";
                  description = "Compatibility tool to use for this app";
                };
              })
            ];
          }
        )
      );

      default = { };
      description = ''
        Configuration for a Steam app.
        App IDs can be found through https://steamdb.info/ or through the game's store page URL.
      '';
    };

  # from home-manager's firefox module
  # https://github.com/nix-community/home-manager/blob/e82585308aef3d4cc2c36c7b6946051c8cdf24ef/modules/programs/firefox/mkFirefoxModule.nix#L151-L175
  mkNoDuplicateAssertion =
    entities: entityKind:
    (
      let
        findDuplicateIds =
          entities: lib.filterAttrs (_: entityNames: lib.length entityNames != 1) (lib.zipAttrs entities);

        duplicates = findDuplicateIds (
          lib.mapAttrsToList (entityName: entity: { "${toString entity.id}" = entityName; }) entities
        );

        mkMsg =
          entityId: entityNames: "  - ID ${entityId} is used by " + lib.concatStringsSep ", " entityNames;
      in
      {
        assertion = duplicates == { };
        message = ''
          Must not have a Steam ${entityKind} with an existing ID but
        ''
        + lib.concatMapAttrsStringSep "\n" mkMsg duplicates;
      }
    );

  usersAppsConfig = cfg.users // {
    shared = {
      id = "shared";
      apps = lib.mapAttrs (_: app: {
        inherit (app) id launchOptions;
      }) cfg.apps;
    };
  };
in
{
  imports = [
    (lib.mkRemovedOptionModule [ "programs" "steam" "localconfig" ] ''
      programs.steam.localconfig has been removed in favor of programs.steam.config
      See the steam-config-nix readme for new usage instructions
    '')

    {
      assertions = [
        (mkNoDuplicateAssertion cfg.users "user")
      ]
      ++ (lib.concatMap (user: user.assertions) (lib.attrValues cfg.users));
    }
  ];

  options.programs.steam.config = {
    enable = lib.mkEnableOption "Steam user config store management";

    package = lib.mkOption {
      default = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.steam-config-patcher;
      description = "The steam-config-patcher package to use.";
      type = types.package;
    };

    steamDir = lib.mkOption {
      type = types.path;
      default = "${config.home.homeDirectory}/.steam/steam";
      description = "Path to the Steam directory.";
    };

    closeSteam = lib.mkEnableOption "automatic closing of Steam when writing configuration changes";

    defaultCompatTool = lib.mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "proton_experimental";
      description = ''
        Default compatibility tool to use for Steam Play
        This option sets the default compatibility tool in Steam, but does not set the nix module defaults
      '';
    };

    apps = mkSteamAppsOption {
      launchOptions = true;
      compatTool = true;
    };

    users = lib.mkOption {
      type = types.attrsOf (
        types.submodule (
          { config, name, ... }:
          {
            imports = [
              (pkgs.path + "/nixos/modules/misc/assertions.nix")
            ];

            options = {
              id = lib.mkOption {
                type = types.int;
                default = lib.strings.toIntBase10 name;
                apply = toSteamId3;
                example = 98765432123456789;
                description = ''
                  The ID for this user in SteamID64 or SteamID3 format.
                  You can find your SteamID64 through https://steamid.io/lookup
                '';
              };

              apps = mkSteamAppsOption { launchOptions = true; };
            };

            config.assertions = [
              (mkNoDuplicateAssertion config.apps "app")
            ];
          }
        )
      );
      default = { };
      description = ''
        Per user configuration for a Steam app.
        User IDs are in SteamID64 or SteamID3 format, for example 98765432123456789
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
      apps."0".compatTool = cfg.defaultCompatTool;

      finalConfig = {
        "KeyValues" = lib.mkMerge [
          (
            let
              compatToolConfigs = lib.filterAttrs (_: app: app.compatTool != null) cfg.apps;
            in
            lib.mkIf (compatToolConfigs != { }) {
              "${cfg.steamDir}/config/config.vdf" = {
                InstallConfigStore.Software.Valve.Steam = {
                  CompatToolMapping = lib.mapAttrs' (_: app: {
                    name = toString app.id;
                    value = {
                      name = app.compatTool;
                      config = "";
                      # app ID 0 represents the default compatibility tool for all games, which should have a priority of 75
                      priority = if (app.id == 0) then "75" else "250";
                    };
                  }) compatToolConfigs;
                };
              };
            }
          )

          (lib.mapAttrs' (_: user: {
            name =
              let
                userDir = lib.replaceString "shared" "*" (toString user.id);
              in
              "${cfg.steamDir}/userdata/${userDir}/config/localconfig.vdf";
            value = {
              UserLocalConfigStore.Software.Valve.Steam.Apps = lib.mapAttrs' (_: app: {
                name = toString app.id;
                value.LaunchOptions = "${makeWrapperPath user.id app.id} %command%";
              }) user.apps;
            };
          }) usersAppsConfig)
        ];

        # "Binary KeyValues" = { };
      };
    };

    home.file = lib.listToAttrs (
      lib.flatten (
        lib.mapAttrsToList (
          _: user:
          lib.mapAttrsToList (_: app: {
            name = makeWrapperPath user.id app.id;
            value.source = lib.getExe app.launchOptions;
          }) (lib.filterAttrs (_: app: app.launchOptions != null) user.apps)
        ) usersAppsConfig
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
