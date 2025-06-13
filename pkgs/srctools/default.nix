{
  pkgs,
  inputs,
  ...
}: let
  selfPkgs = inputs.self.packages.${pkgs.system};
in
  pkgs.python313Packages.buildPythonPackage rec {
    pname = "srctools";
    version = "2.6.0";
    format = "pyproject";

    src = pkgs.fetchPypi {
      inherit pname version;
      sha256 = "4073d14a0bb78b8e3790b78b7895d5a4f3f486a31bb22e2549c0181ebadf5843";
    };

    nativeBuildInputs = with selfPkgs; [
      meson
      meson-python
      cython
    ];

    propagatedBuildInputs = [
      pkgs.python313Packages.attrs
      selfPkgs.useful-types
    ];

    pythonImportsCheck = ["srctools"];

    meta = {
      description = "Modules for working with Valve's Source Engine file formats";
      homepage = "https://github.com/TeamSpen210/srctools";
      license = pkgs.lib.licenses.unlicense;
      mainProgram = "srctools";
      platforms = pkgs.lib.platforms.all;
    };
  }
