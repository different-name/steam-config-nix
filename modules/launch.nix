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
    dataDir
    homeRelative
    launchShellPath
    allApps
    ;
  envLib = import ../lib/env.nix { inherit lib; };

  launchDir = "${dataDir}/launch";
  launchExe = lib.getExe cfg.packages.launch;

  globalSpec = pkgs.writeText "steam-config-nix-launch-global.json" (
    lib.toJSON {
      version = 1;
      inherit (cfg) notifySend;
      env = envLib.toSpec cfg.env;
    }
  );
  appSpecs = lib.listToAttrs (
    map (
      app:
      lib.nameValuePair (toString app.id) (
        pkgs.writeText "steam-config-nix-launch-${toString app.id}.json" (lib.toJSON app.launchSpec)
      )
    ) (lib.filter (app: app.launchSpec != null) allApps)
  );
  specFiles = {
    "global.json" = globalSpec;
  }
  // lib.mapAttrs' (id: lib.nameValuePair "${id}.json") appSpecs;
  # one store link for the whole directory, so a removed app's spec goes with it
  launchTree = pkgs.linkFarm "steam-config-nix-launch" specFiles;
  launchLinks = lib.mapAttrs' (
    file: source: lib.nameValuePair (homeRelative "${launchDir}/${file}") { inherit source; }
  ) specFiles;
in
{
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.optionalAttrs isNixos {
        systemd.tmpfiles.rules = [
          "L+ ${launchShellPath} - - - - ${launchExe}"
          "L+ ${launchDir} - - - - ${launchTree}"
          "r ${dataDir}/apps"
          "r ${dataDir}/launch-env.sh"
        ];

        environment.systemPackages = [ cfg.packages.launch ];
      })

      (lib.optionalAttrs (!isNixos) {
        home.file =
          launchLinks
          // lib.optionalAttrs (!layered) {
            # replaces the copy earlier versions installed at this path
            ${homeRelative launchShellPath} = {
              source = launchExe;
              force = true;
            };
          };

        home.packages = [ cfg.packages.launch ];
      })
    ]
  );
}
