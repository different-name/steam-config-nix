{pkgs, ...}:
pkgs.python313Packages.meson.overrideAttrs (finalAttrs: previousAttrs: {
  version = "1.8.0";

  src = pkgs.fetchFromGitHub {
    owner = "mesonbuild";
    repo = "meson";
    tag = finalAttrs.version;
    hash = "sha256-Y1G3kHSv1krlJjR7oHcN8GavzYj2C25GLq8lvYpnMKA=";
  };

  patches =
    (pkgs.lib.take (pkgs.lib.length previousAttrs.patches - 1) previousAttrs.patches)
    ++ [
      ./007-freebsd-pkgconfig-path.patch
    ];
})
