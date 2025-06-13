{pkgs, ...}:
pkgs.python313Packages.meson-python.overrideAttrs (finalAttrs: previousAttrs: {
  version = "0.18.0";

  src = pkgs.fetchPypi {
    inherit (finalAttrs) version;
    pname = "meson_python";
    sha256 = "c56a99ec9df669a40662fe46960321af6e4b14106c14db228709c1628e23848d";
  };
})
