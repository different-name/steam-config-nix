{ lib, pkgs }:
rec {
  # chaotic's proton-cachyos nests the vdf under bin/ with no steamcompattool output
  compatToolDir =
    pkg:
    let
      base = lib.getOutput "steamcompattool" pkg;
    in
    pkgs.runCommand "${lib.getName pkg}-steamcompattool"
      {
        preferLocalBuild = true;
        allowSubstitutes = false;
      }
      ''
        if [ -f ${lib.escapeShellArg "${base}/compatibilitytool.vdf"} ]; then
          ln -s ${lib.escapeShellArg base} "$out"
        elif [ -f ${lib.escapeShellArg "${base}/bin/compatibilitytool.vdf"} ]; then
          ln -s ${lib.escapeShellArg "${base}/bin"} "$out"
        else
          echo "steam-config-nix: no compatibilitytool.vdf found in ${base} or ${base}/bin" >&2
          exit 1
        fi
      '';
  compatToolValue =
    tool:
    if tool == null then
      null
    else if lib.isDerivation tool then
      { path = compatToolDir tool; }
    else
      tool;
}
