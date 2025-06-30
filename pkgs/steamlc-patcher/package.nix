{
  lib,
  buildPythonApplication,
  setuptools,
  srctools,
  psutil,
  ...
}:
buildPythonApplication {
  pname = "steamlc-patcher";
  version = "0.1.0";

  src = builtins.path {
    path = ../../src;
    name = "steamlc-patcher-src";
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
    description = "Configure Steam's localconfig.vdf using JSON file input";
    homepage = "https://github.com/different-name/steamlc-patcher";
    license = lib.licenses.gpl3Plus;
    mainProgram = "steamlc-patcher";
    platforms = lib.platforms.all;
  };
}
