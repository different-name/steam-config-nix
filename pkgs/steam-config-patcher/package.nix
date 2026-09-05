{
  lib,
  buildPythonApplication,
  setuptools,
  psutil,
  pydantic,
  pillow,
  pytestCheckHook,
}:
buildPythonApplication {
  pname = "steam-config-patcher";
  version = (lib.importTOML ../../patcher/pyproject.toml).project.version;

  src = builtins.path {
    path = ../../patcher;
    name = "steam-config-patcher-src";
  };

  pyproject = true;

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
    platforms = lib.platforms.linux;
  };
}
