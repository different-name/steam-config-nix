{
  pkgs,
  inputs,
  ...
}:
pkgs.python313Packages.buildPythonApplication {
  pname = "steam-launch-setter";
  version = "0.1.0";

  src = ../../steam-launch-setter;

  format = "pyproject";

  nativeBuildInputs = [
    pkgs.python313Packages.setuptools
  ];

  propagatedBuildInputs = [
    inputs.self.packages.${pkgs.system}.srctools
    pkgs.python313Packages.psutil
  ];

  meta = {
    description = "Update Steam launch options in localconfig.vdf files using JSON file input";
    homepage = "https://github.com/different-name/steam-launch.nix";
    license = pkgs.lib.licenses.unlicense;
    mainProgram = "steam-launch-setter";
    platforms = pkgs.lib.platforms.all;
  };
}
