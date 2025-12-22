{ self, dataDir }:
{ lib, pkgs, ... }:
let
  inherit (lib) types;

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
  };
}
