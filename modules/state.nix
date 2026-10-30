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
    dataDir
    homeRelative
    stateFile
    enabledApps
    enabledNonSteamApps
    keepPath
    ;
  inherit (import ../lib/compat-tool.nix { inherit lib pkgs; }) compatToolValue;

  artworkPaths =
    artwork:
    lib.filterAttrs (_: v: v != null) (
      lib.mapAttrs (_: v: if v == null then null else keepPath v) artwork
    );

  updateValues = {
    default = 0;
    onLaunch = 1;
    highPriority = 2;
  };
  downloadValues = {
    default = 0;
    always = 1;
    never = 2;
  };
  inputValues = {
    default = 1;
    enable = 2;
  };
  mapped = table: v: if v == null then null else table.${v};

  state = {
    inherit (cfg) onSteamRunning;
    steam = lib.getExe cfg.launcher;
    inherit (cfg) notifySend;
    libraryFolders = map toString cfg.libraryFolders;
  }
  // lib.filterAttrs (_: v: v != null) {
    globalCompatTool = compatToolValue cfg.defaultCompatTool;
    inherit (cfg) displayRatesAsBits desktopUiScale;
  }
  // {
    apps = lib.mapAttrs' (
      _: app:
      lib.nameValuePair (toString app.id) (
        lib.filterAttrs (_: v: v != null && v != { }) {
          compatTool = compatToolValue app.compatTool;
          beta = app.betaBranch;
          inherit (app) language overlay;
          libraryIcon =
            app.desktopEntry.enable
            && app.desktopEntry.useLibraryIcon
            && app.desktopEntry.icon == "steam-config-nix-${toString app.id}";
          steamInput = mapped inputValues app.steamInput;
          updateBehavior = mapped updateValues app.updateBehavior;
          backgroundDownloads = mapped downloadValues app.allowDownloadsWhileRunning;
          artwork = artworkPaths app.artwork;
        }
      )
    ) enabledApps;
    shortcuts = lib.mapAttrs' (
      _: app:
      lib.nameValuePair (toString app.id) (
        lib.filterAttrs (_: v: v != null && v != { }) {
          inherit (app) name overlay hidden;
          exe = keepPath app.target;
          dir = app.startIn;
          icon = if app.artwork.icon == null then null else keepPath app.artwork.icon;
          vr = app.inVrLibrary;
          compatTool = compatToolValue app.compatTool;
          artwork = artworkPaths (removeAttrs app.artwork [ "icon" ]);
        }
      )
    ) enabledNonSteamApps;
  };
  stateJson = pkgs.writeText "steam-config-nix-state.json" (lib.toJSON state);
in
{
  options.programs.steam-config.stateJson = lib.mkOption {
    type = lib.types.package;
    default = stateJson;
    readOnly = true;
    internal = true;
    visible = false;
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.optionalAttrs isNixos {
        systemd.tmpfiles.rules = [
          "d ${dataDir} 0755 root root -"
          "L+ ${stateFile} - - - - ${stateJson}"
        ];
      })

      (lib.optionalAttrs (!isNixos) {
        home.file.${homeRelative stateFile}.source = stateJson;
      })
    ]
  );
}
