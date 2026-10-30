{ format }:
{
  lib,
  config,
  pkgs,
  osConfig ? null,
  ...
}:
let
  inherit
    (import ../lib/context.nix {
      inherit
        lib
        config
        osConfig
        format
        ;
    })
    cfg
    isNixos
    layered
    allApps
    ;
  inherit (import ../lib/compat-tool.nix { inherit lib pkgs; }) compatToolDir;

  compatToolPackages = lib.unique (
    lib.filter lib.isDerivation ([ cfg.defaultCompatTool ] ++ map (app: app.compatTool) allApps)
  );
  osCompatToolPaths = map toString (
    lib.optionals layered (osConfig.programs.steam.extraCompatPackages or [ ])
  );
  userCompatToolPackages = lib.filter (
    pkg: !(lib.elem (toString pkg) osCompatToolPaths)
  ) compatToolPackages;
in
{
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.optionalAttrs isNixos {
        programs.steam.extraCompatPackages = compatToolPackages;
      })

      (lib.optionalAttrs (!isNixos) {
        home.file = lib.listToAttrs (
          map (
            pkg:
            lib.nameValuePair ".local/share/Steam/compatibilitytools.d/${lib.getName pkg}" {
              source = compatToolDir pkg;
            }
          ) userCompatToolPackages
        );
      })
    ]
  );
}
