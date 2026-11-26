{
  lib,
  config,
  osConfig,
  format,
}:
rec {
  cfg = config.programs.steam-config;
  isNixos = format == "nixos";

  osSteamConfig =
    if isNixos || osConfig == null then null else osConfig.programs.steam-config or null;
  # under an enabled nixos module, home manager leaves the plumbing to it
  layered = osSteamConfig != null && osSteamConfig.enable;

  dataDir =
    if isNixos then "/var/lib/steam-config-nix" else "${config.xdg.dataHome}/steam-config-nix";
  homeRelative = path: lib.removePrefix "${config.home.homeDirectory}/" path;
  userDataDir = ''"''${XDG_DATA_HOME:-$HOME/.local/share}/steam-config-nix"'';
  stateFile = "${dataDir}/state.json";
  launchShellPath = "${dataDir}/launch-shell";

  enabledApps = lib.filterAttrs (_: app: app.enable) cfg.apps;
  enabledNonSteamApps = lib.filterAttrs (_: app: app.enable) cfg.nonSteamApps;
  allApps = lib.attrValues enabledApps ++ lib.attrValues enabledNonSteamApps;

  keepPath = import ./keep-path.nix { inherit lib; };
}
