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
    userDataDir
    stateFile
    allApps
    keepPath
    ;
  inherit (cfg) stateJson;

  systemctl = lib.getExe' pkgs.systemd "systemctl";

  patcherCommand = pkgs.writeShellScript "steam-config-nix-patch" ''
    exec ${lib.getExe cfg.packages.patcher} ${
      if isNixos then
        "${userDataDir}/state.json ${lib.escapeShellArg stateFile}"
      else
        lib.escapeShellArg stateFile
    }
  '';
  startPatcher = "${systemctl} --user start --no-block steam-config-patcher.service";

  desktopEntryApps = lib.filter (app: app.desktopEntry.enable) allApps;

  mkDesktopEntry = app: {
    key = "steam-config-nix-${app.key}";
    exec = "${lib.getExe cfg.launcher} steam://rungameid/${app.steamRunId}";
    inherit (app.desktopEntry)
      name
      genericName
      comment
      icon
      categories
      ;
  };

  systemdApps = lib.filter (app: app.systemd.enable) allApps;
  docsUrl = "https://different-name.github.io/steam-config-nix/docs/run-alongside-game/";
  renderUnitValue =
    value:
    if lib.isBool value then
      (if value then "yes" else "no")
    else if lib.isList value then
      lib.concatStringsSep " " value
    else
      toString value;
  sharedTargetUnit = {
    Description = "A Steam app is running";
    Documentation = docsUrl;
    StopWhenUnneeded = "yes";
    RefuseManualStart = "yes";
    RefuseManualStop = "yes";
  };
  mkTargetUnit =
    app:
    {
      Description = app.name;
      Documentation = docsUrl;
      StopWhenUnneeded = "yes";
      RefuseManualStart = "yes";
      RefuseManualStop = "yes";
      Wants = "steam-app.target";
      After = "steam-app.target";
    }
    // lib.mapAttrs (_: renderUnitValue) app.systemd.target.unitConfig;
  targetUnits =
    lib.optionalAttrs (systemdApps != [ ]) { steam-app = sharedTargetUnit; }
    // lib.listToAttrs (
      map (app: lib.nameValuePair "steam-app-${app.systemd.target.name}" (mkTargetUnit app)) systemdApps
    );
in
{
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.optionalAttrs isNixos {
        systemd.user.services.steam-config-patcher = {
          description = "Steam configuration patcher";
          wantedBy = [ "default.target" ];
          restartTriggers = [ stateJson ];
          serviceConfig = {
            Type = "exec";
            ExecStart = patcherCommand;
          };
        };
        system.userActivationScripts.steam-config-nix = startPatcher;

        systemd.user.targets = lib.mapAttrs (_: unit: { unitConfig = unit; }) targetUnits;

        environment.systemPackages = map (
          app:
          let
            entry = mkDesktopEntry app;
          in
          pkgs.makeDesktopItem (
            {
              inherit (entry) exec categories comment;
              name = entry.key;
              desktopName = entry.name;
              type = "Application";
              terminal = false;
            }
            // lib.optionalAttrs (entry.genericName != null) { inherit (entry) genericName; }
            // lib.optionalAttrs (entry.icon != null) { icon = keepPath entry.icon; }
          )
        ) desktopEntryApps;
      })

      (lib.optionalAttrs (!isNixos) {
        systemd.user.services.steam-config-patcher = lib.mkIf (!layered) {
          Unit = {
            Description = "Steam configuration patcher";
            X-Restart-Triggers = [ "${stateJson}" ];
          };
          Service = {
            Type = "exec";
            ExecStart = patcherCommand;
          };
          Install.WantedBy = [ "default.target" ];
        };
        home.activation.steam-config-nix-patcher = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
          if ${systemctl} --user show --property=Version >/dev/null 2>&1; then
            run ${startPatcher} || warnEcho "steam-config-patcher.service could not be started, it runs at the next login"
          fi
        '';

        systemd.user.targets = lib.mapAttrs (_: unit: { Unit = unit; }) targetUnits;

        # a standalone home manager cannot see the system's configuration, so it can only say so here
        home.activation.steam-config-nix-system = lib.mkIf (osConfig == null) (
          lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            if [ -e /etc/systemd/user/steam-config-patcher.service ]; then
              warnEcho "programs.steam-config is also enabled in this machine's NixOS configuration. This Home Manager configuration replaces it for $USER."
            fi
          ''
        );

        xdg.desktopEntries = lib.listToAttrs (
          map (
            app:
            let
              entry = mkDesktopEntry app;
            in
            lib.nameValuePair entry.key {
              inherit (entry)
                name
                genericName
                comment
                exec
                categories
                icon
                ;
              type = "Application";
              terminal = false;
            }
          ) desktopEntryApps
        );
      })
    ]
  );
}
