{
  lib,
  buildPythonApplication,
  setuptools,
  srctools,
  vdf,
  psutil,
  pydantic,
  ...
}:
buildPythonApplication {
  pname = "steam-config-patcher";
  version = "0.2.3";

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
    # patching vdf to support the int format that shortcuts.vdf uses
    (vdf.overridePythonAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        (builtins.path {
          path = ./vdf-int-fix.diff;
          name = "vdf-int-fix";
        })
      ];
    }))
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
