{
  lib,
  buildPythonApplication,
  setuptools,
  psutil,
  pydantic,
  pillow,
  pytestCheckHook,
  ...
}:
buildPythonApplication {
  pname = "steam-config-patcher";
  version = "0.4.0";

  src = builtins.path {
    path = ../../src;
    name = "steam-config-patcher-src";
  };

  format = "pyproject";

  build-system = [
    setuptools
  ];

  propagatedBuildInputs = [
    psutil
    pydantic
    pillow
  ];

  nativeCheckInputs = [ pytestCheckHook ];

  meta = {
    description = "Patch Steam vdf files using JSON input";
    homepage = "https://github.com/different-name/steam-config-nix";
    license = lib.licenses.gpl3Plus;
    mainProgram = "steam-config-patcher";
    platforms = lib.platforms.all;
  };
}
