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

  cfg = config.programs.steam.localConfig;
  steam-config-patcher = inputs.self.packages.${pkgs.system}.steam-config-patcher;

  genLocalConfig = userId: userCfg: {
    name = "${config.home.homeDirectory}/.steam/steam/userdata/${userId}/config/localconfig.vdf";
    value = lib.recursiveUpdate {
      UserLocalConfigStore.Software.Valve.Steam.Apps = lib.mapAttrs (name: value: {
        LaunchOptions = value;
      }) userCfg.launchOptions;
    } userCfg.extraConfig;
  };

  jsonFile = lib.pipe cfg.users [
    (lib.mapAttrsToList genLocalConfig)
    lib.listToAttrs
    builtins.toJSON
    (builtins.toFile "steamlc-json")
  ];

  arguments =
    lib.cli.toGNUCommandLine { } {
      close-steam = cfg.closeSteam;
    }
    ++ [ jsonFile ];
in
{
  options.programs.steam = {
    localConfig = {
      enable = lib.mkEnableOption "Steam user config store management";

      closeSteam = lib.mkEnableOption "automatic closing of Steam when writing configuration changes";

      users = lib.mkOption {
        type = types.attrsOf (
          types.submodule {
            options = {
              launchOptions = lib.mkOption {
                type = types.attrsOf types.str;
                default = { };
                example = {
                  "438100" = ''env -u TZ PRESSURE_VESSEL_FILESYSTEMS_RW="$XDG_RUNTIME_DIR/wivrn/comp_ipc" %command%'';
                  "620" = ''%command% -vulkan'';
                };
                description = ''
                  Per-game launch options keyed by Steam App ID
                '';
              };

              extraConfig = lib.mkOption {
                type = nestedAttrsOfStrings;
                default = { };
                example = {
                  UserLocalConfigStore.Software.Valve.Steam = {
                    Apps = {
                      "438100" = {
                        LaunchOptions = ''env -u TZ PRESSURE_VESSEL_FILESYSTEMS_RW="$XDG_RUNTIME_DIR/wivrn/comp_ipc" %command%'';
                      };
                      "620" = {
                        LaunchOptions = ''%command% -vulkan'';
                      };
                    };
                  };
                };
                description = ''
                  Extra config options to be patched into localconfig.vdf
                '';
              };
            };
          }
        );

        default = { };
        example = "987654321";
        description = ''
          Local config values for a Steam user
          User IDs are in steamID3 format, without [] or the U:1: prefix
          For example [U:1:987654321] -> 987654321
          User IDs can be found through https://steamid.io/lookup or in ~/.steam/steam/userdata
        '';
      };
    };

    config = lib.mkIf (cfg.enable) {
      home.activation.steam-config-patcher = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${lib.getExe steam-config-patcher} ${lib.concatStringsSep " " arguments}
      '';
    };
  };
}
