{
  lib,
  config,
  inputs,
  pkgs,
  ...
}:
let
  inherit (lib) types;
  nestedAttrsOfStrings = types.lazyAttrsOf (types.either types.str nestedAttrsOfStrings);

  # modified from home-manager lib.shell.exportAll
  # https://github.com/nix-community/home-manager/blob/89c9508bbe9b40d36b3dc206c2483ef176f15173/modules/lib/shell.nix#L36-L42
  exportUnset = n: v: if v == null then "unset ${n}" else ''export ${n}="${toString v}"'';
  exportAll = lib.concatMapAttrsStringSep "\n" exportUnset;

  cfg = config.programs.steam.config;

  dataDir = "${config.xdg.dataHome}/steam-config-nix";

  # get a SteamID3 from a SteamID64
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
    userId:
    {
      supportCompatTool ? false,
    }:
    lib.mkOption {
      type = types.attrsOf (
        types.submodule (
          { config, name, ... }:
          {
            options = {
              id = lib.mkOption {
                type = types.int;
                default = lib.strings.toIntBase10 name;
                example = 438100;
                description = ''
                  The ID for this app.
                  App IDs can be found through https://steamdb.info/ or through the game's store page URL.
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
                example = "-vulkan";
                description = "Game launch options";
                apply =
                  value:
                  if (lib.isDerivation value) || value == null then
                    value
                  else
                    writeLaunchOptionsSetBin config.id value;
              };

              wrapperPath = lib.mkOption {
                type = types.nullOr types.path;
                default = "${dataDir}/users/${toString userId}/app-wrappers/${toString config.id}";
                example = "/home/diffy/1361210-wrapper";
                description = "A stable path outside of the nix store to link the app wrapper script";
              };
            }
            // (lib.optionalAttrs supportCompatTool {
              compatTool = lib.mkOption {
                type = types.nullOr types.str;
                default = null;
                example = "proton_experimental";
                description = "Compatibility tool to use for this app";
              };
            });
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

    apps = mkSteamAppsOption "shared" { supportCompatTool = true; };

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

              apps = mkSteamAppsOption config.id { };
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
  };

  config = lib.mkIf cfg.enable {
    home.file =
      let
        userAppConfigs = cfg.users // {
          shared = {
            id = "shared";
            apps = lib.mapAttrs (_: app: {
              inherit (app) id launchOptions wrapperPath;
            }) cfg.apps;
          };
        };
      in
      lib.listToAttrs (
        lib.flatten (
          lib.mapAttrsToList (
            _: user:
            lib.mapAttrsToList (_: app: {
              name = app.wrapperPath;
              value.source = lib.getExe app.launchOptions;
            }) (lib.filterAttrs (_: app: app.launchOptions != null) user.apps)
          ) userAppConfigs
        )
      );

    home.activation.steam-config-patcher = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${lib.getExe cfg.package} ${lib.escapeShellArg (builtins.toJSON cfg)}
    '';
  };
}
