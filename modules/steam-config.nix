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
      exec env ${lib.replaceString "%command%" ''"$@"'' launchOptions}
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

  steam-config-patcher = inputs.self.packages.${pkgs.system}.steam-config-patcher;

  # Get a Steam3ID from a Steam64ID
  # https://gist.github.com/bcahue/4eae86ae1d10364bb66d
  getId3 =
    userId:
    let
      steamId64Ident = 76561197960265728;
      userIdInt = lib.strings.toIntBase10 userId;
      isSteam64 = userId != "*" && userIdInt >= steamId64Ident;
    in
    if isSteam64 then toString (userIdInt - steamId64Ident) else userId;

  arguments = lib.cli.toGNUCommandLineShell { } {
    json = builtins.toJSON (config.programs.steam.config.extraConfig);
    close-steam = cfg.closeSteam;
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

        (lib.mapAttrs' (
          userId: user:
          let
            steamID = getId3 userId;
          in
          {
            name = "${steamDir}/userdata/${steamID}/config/localconfig.vdf";
            value = {
              UserLocalConfigStore.Software.Valve.Steam.Apps = lib.mapAttrs (appId: app: {
                LaunchOptions = "${config.xdg.dataHome}/${genWrapperPath steamID appId} %command%";
              }) user.apps;
            };
          }
        ) cfg.users)
      ];
    };

    xdg.dataFile = lib.listToAttrs (
      lib.flatten (
        lib.mapAttrsToList (
          userId: user:
          lib.mapAttrsToList (appId: app: {
            name = genWrapperPath (getId3 userId) appId;
            value.source = lib.getExe app.launchOptions;
          }) (lib.filterAttrs (_: app: app.launchOptions != null) user.apps)
        ) cfg.users
      )
    );

    home.activation.steam-config-patcher = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${lib.getExe steam-config-patcher} ${arguments}
    '';
  };
}
