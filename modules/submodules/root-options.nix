{
  self,
  dataDir,
  format,
}:
{
  lib,
  pkgs,
  config,
  osConfig,
  ...
}:
let
  inherit (lib) types;

  cfg = config.programs.steam.config;

  rootOptionPath = [
    "programs"
    "steam"
    "config"
  ];
in
{
  imports = [
    (import ./apps-option.nix {
      inherit dataDir rootOptionPath;
      userId = "shared";
      supportCompatTool = true;
    })
    (import ./users-option.nix {
      inherit dataDir rootOptionPath;
    })
  ];

  options.programs.steam.config = {
    enable = lib.mkEnableOption "declarative Steam configuration";

    package = lib.mkOption {
      type = types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.steam-config-patcher;
      description = "The steam-config-patcher package to use.";
    };

    shutdownBehavior = lib.mkOption {
      type = types.nullOr (
        types.either (types.enum [
          "close"
          "restart"
        ]) (types.listOf types.str)
      );
      default = null;
    };

    restartCmdline =
      let
        steamPkg =
          if (format == "home-manager") then
            osConfig.programs.steam.package
          else
            config.programs.steam.package;
      in
      lib.mkOption {
        type = types.listOf types.str;
        default = lib.optionals (cfg.shutdownBehavior == null) (
          [
            (lib.getExe' pkgs.systemd "systemd-run")
            "--user"
            "--scope"
          ]
          ++ (if (cfg.shutdownBehavior == "restart") then [ (lib.getExe steamPkg) ] else cfg.shutdownBehavior)
        );
        readOnly = true;
        internal = true;
        visible = false;
      };

    defaultCompatTool = lib.mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "proton_experimental";
      description = ''
        Default compatibility tool to use for Steam Play.

        This option sets the default compatibility tool in Steam, but does not set the nix module defaults.
      '';
    };
  };
}
