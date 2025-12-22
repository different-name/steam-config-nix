self:
{ lib, config, ... }:
let
  inherit (import ./lib.nix lib) generateLaunchOptionLinks;
  cfg = config.programs.steam.config;

  dataHome = "/etc";
  dataDir = "${dataHome}/steam-config-nix";
in
{
  imports = [
    (import ./submodules/root-options.nix { inherit self dataDir; })
  ];

  config = lib.mkIf cfg.enable {
    environment.etc = generateLaunchOptionLinks cfg dataHome;
  };
}
