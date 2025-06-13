{pkgs, ...}:
pkgs.python313Packages.buildPythonPackage rec {
  pname = "useful-types";
  version = "0.2.1";
  format = "pyproject";

  src = pkgs.fetchPypi {
    inherit version;
    pname = "useful_types";
    sha256 = "870a0bcc8fcb7d0b2f14055438c1cab7e248fded942b0943a4d7019e7fbbdacd";
  };

  nativeBuildInputs = [
    pkgs.python313Packages.flit-core
  ];

  propagatedBuildInputs = [
    pkgs.python313Packages.typing-extensions
  ];

  pythonImportsCheck = ["useful_types"];

  meta = {
    description = "Useful types for Python";
    homepage = "https://github.com/hauntsaninja/useful_types";
    changelog = "https://github.com/hauntsaninja/useful_types/blob/${src.rev}/CHANGELOG.md";
    license = pkgs.lib.licenses.mit;
    mainProgram = "useful-types";
  };
}
