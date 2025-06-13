{pkgs, ...}:
pkgs.python313Packages.cython.overrideAttrs (finalAttrs: previousAttrs: {
  version = "3.1.0";

  src = pkgs.fetchPypi {
    inherit (finalAttrs) version;
    inherit (previousAttrs) pname;
    sha256 = "1097dd60d43ad0fff614a57524bfd531b35c13a907d13bee2cc2ec152e6bf4a1";
  };
})
