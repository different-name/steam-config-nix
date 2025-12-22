self:
{ lib, config, ... }:
let
  inherit (import ./lib.nix lib) generateLaunchOptionLinks;
  cfg = config.programs.steam.config;

  dataHome = config.xdg.dataHome;
  dataDir = "${dataHome}/steam-config-nix";
in
{
  imports = [
    (import ./submodules/root-options.nix { inherit self dataDir; })
  ];

  config = lib.mkIf cfg.enable {
    xdg.dataFile = generateLaunchOptionLinks cfg dataHome;

    home.activation.steam-config-patcher = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${lib.getExe cfg.package} ${lib.escapeShellArg (builtins.toJSON cfg)}
    '';
  };
}
