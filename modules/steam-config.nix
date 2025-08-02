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

  genWrapperName = appId: "app-${appId}-wrapped";
  genWrapperPath =
    userId: appId: "steam-config-nix/${lib.replaceString "*" "common" userId}/${genWrapperName appId}";

  genLaunchOptionPackage =
    appId: launchOptions:
    pkgs.writeShellScriptBin (genWrapperName appId) ''
      exec ${lib.replaceString "%command%" ''"$@"'' launchOptions}
    '';

  mkSteamAppsOption =
    {
      launchOptions ? false,
      compatTool ? false,
    }:
    lib.mkOption {
      type = types.attrsOf (
        types.submodule (
          { name, ... }:
          {
            options = lib.mergeAttrsList [
              (lib.optionalAttrs launchOptions {
                launchOptions = lib.mkOption {
                  type = types.nullOr (types.coercedTo types.str (genLaunchOptionPackage name) types.package);
                  default = null;
                  example = "%command% -vulkan";
                  description = "Game launch options";
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
          }
        )
      );

      default = { };
      description = ''
        Configuration for a Steam app
        App IDs can be found through https://steamdb.info/ or through the game's store page URL
      '';
    };

  cfg = config.programs.steam.config;
  steamDir = "${config.home.homeDirectory}/.steam/steam";

  arguments = lib.cli.toGNUCommandLine { } {
    json = builtins.toJSON (config.programs.steam.config.extraConfig);
    close-steam = cfg.closeSteam;
  };

  steam-config-patcher = inputs.self.packages.${pkgs.system}.steam-config-patcher;
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
        User IDs are in steamID3 format, without [] or the U:1: prefix
        For example [U:1:987654321] -> 987654321
        User IDs can be found through https://steamid.io/lookup or in ~/.steam/steam/userdata
      '';
    };

    extraConfig = lib.mkOption {
      type = nestedAttrsOfStrings;
      visible = false;
      default = { };
    };
  };

  config = lib.mkIf (cfg.enable) {
    programs.steam.config = {
      users."*".apps = lib.mapAttrs (_: app: { inherit (app) launchOptions; }) cfg.apps;

      extraConfig = lib.mkMerge [
        (
          let
            compatToolConfigs = lib.filterAttrs (_: app: app.compatTool != null) cfg.apps;
          in
          lib.mkIf (compatToolConfigs != { }) {
            "${steamDir}/config/config.vdf" = {
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

        (lib.mapAttrs' (userId: user: {
          name = "${steamDir}/userdata/${userId}/config/localconfig.vdf";
          value = {
            UserLocalConfigStore.Software.Valve.Steam.Apps = lib.mapAttrs (appId: app: {
              LaunchOptions = "${config.xdg.dataHome}/${genWrapperPath userId appId} %command%";
            }) user.apps;
          };
        }) cfg.users)
      ];
    };

    xdg.dataFile =
      cfg.users
      |> lib.mapAttrsToList (
        userId: user:
        lib.mapAttrsToList (appId: app: {
          name = genWrapperPath userId appId;
          value.source = lib.getExe app.launchOptions;
        }) user.apps
      )
      |> lib.flatten
      |> lib.listToAttrs;

    home.activation.steam-config-patcher = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${lib.getExe steam-config-patcher} ${lib.escapeShellArgs arguments}
    '';
  };
}
