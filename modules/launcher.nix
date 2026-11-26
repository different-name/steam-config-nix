{ format }:
{
  lib,
  config,
  pkgs,
  osConfig ? null,
  ...
}:
let
  inherit (lib) types;
  cfg = config.programs.steam-config;
  isNixos = format == "nixos";

  launcher = pkgs.writeShellScriptBin "steam" ''
    export STEAM_GAME_LAUNCH_SHELL=${lib.escapeShellArg (toString cfg.launchShell)}
    exec ${lib.getExe cfg.steamPackage} "$@"
  '';
in
{
  options.programs.steam-config = {
    steamPackage = lib.mkOption {
      type = types.package;
      default =
        if isNixos then
          config.programs.steam.package
        else if osConfig != null then
          osConfig.programs.steam.package
        else
          pkgs.steam;
      defaultText = lib.literalMD "`programs.steam.package`, from the NixOS configuration under Home Manager's NixOS module, otherwise `pkgs.steam`";
      description = "The Steam package the `steam` launcher starts.";
    };

    launcher = lib.mkOption {
      type = types.package;
      default = launcher;
      defaultText = lib.literalMD "the generated launcher";
      readOnly = true;
      description = ''
        The `steam` launcher this module installs. Use `''${config.programs.steam-config.launcher}/bin/steam` in a script, autostart entry or unit that starts Steam.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    if isNixos then
      {
        environment.systemPackages = [ (lib.hiPrio launcher) ];
        assertions = [
          {
            assertion = config.programs.steam.enable;
            message = "programs.steam-config needs `programs.steam.enable = true`.";
          }
        ];
      }
    else
      { home.packages = [ (lib.hiPrio launcher) ]; }
  );
}
