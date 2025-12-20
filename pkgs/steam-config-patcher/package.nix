{
  lib,
  buildPythonApplication,
  setuptools,
  srctools,
  psutil,
  pydantic,
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
    pydantic
  ];

  meta = {
    description = "Patch Steam vdf files using JSON input";
    homepage = "https://github.com/different-name/steam-config-nix";
    license = lib.licenses.gpl3Plus;
    mainProgram = "steam-config-patcher";
    platforms = lib.platforms.all;
  };
}
