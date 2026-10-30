{ lib }:
let
  keepPath = import ./keep-path.nix { inherit lib; };
  render = v: if lib.isFloat v then lib.toJSON v else keepPath v;
in
{
  type =
    with lib.types;
    lazyAttrsOf (
      nullOr (oneOf [
        str
        path
        int
        float
        bool
      ])
    );

  toSpec = lib.mapAttrs (_: v: if v == null then null else render v);
}
