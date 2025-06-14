{
  config,
  lib,
  inputs,
  pkgs,
  ...
}: let
  cfg = config.programs.steam-launch;
in {
  options.programs.steam-launch = {
    enable = lib.mkEnableOption "per-game Steam launch options configuration";
    stopSteam = lib.mkEnableOption "automatic closing of steam if it is running when modifying config";

    options = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Per-game launch options keyed by Steam App ID. Values are passed as-is to Steam.";
      example = {
        "438100" = ''env -u TZ PRESSURE_VESSEL_FILESYSTEMS_RW="$XDG_RUNTIME_DIR/wivrn/comp_ipc" %command%'';
        "620" = "%command% -vulkan";
      };
    };
  };

  config = lib.mkIf (cfg.enable && cfg.options != {}) {
    home.activation.steam-launch-setter = let
      steam-launch-setter-exe = lib.getExe inputs.self.packages.${pkgs.system}.steam-launch-setter;
      launch-options-json-file = builtins.toFile "steam-launch-options.json" (builtins.toJSON cfg.options);
    in
      lib.hm.dag.entryAfter ["writeBoundary"] ''
        run ${steam-launch-setter-exe} ${launch-options-json-file}${lib.optionalString cfg.stopSteam " -f"}
      '';
  };
}
