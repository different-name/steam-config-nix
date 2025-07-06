{
  lib,
  buildPythonApplication,
  setuptools,
  srctools,
  psutil,
  ...
}:
buildPythonApplication {
  pname = "steam-config-patcher";
  version = "0.1.0";

  src = builtins.path {
    path = ../../src;
    name = "steam-config-patcher-src";
  };

  format = "pyproject";

  build-system = [
    setuptools
  ];

  propagatedBuildInputs = [
    srctools
    psutil
  ];

  meta = {
    description = "Patch Steam vdf files using JSON file input";
    homepage = "https://github.com/different-name/steam-config-nix";
    license = lib.licenses.gpl3Plus;
    mainProgram = "steam-config-patcher";
    platforms = lib.platforms.all;
  };
}
