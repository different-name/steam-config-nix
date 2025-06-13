{
  pkgs,
  inputs,
  ...
}: let
  mkPackageAttr = path: let
    package = import path {inherit pkgs inputs;};
  in {
    name = package.pname or package.name;
    value = package;
  };
in
  [
    ./steam-launch-setter

    # available in nixpkgs, but outdated
    ./cython
    ./meson
    ./meson-python

    # unavailable in nixpkgs
    ./srctools
    ./useful-types
  ]
  |> map mkPackageAttr
  |> builtins.listToAttrs
