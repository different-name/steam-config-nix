lib:
let
  steamConfigLib = {
    # modified from home-manager lib.shell.exportAll
    # https://github.com/nix-community/home-manager/blob/89c9508bbe9b40d36b3dc206c2483ef176f15173/modules/lib/shell.nix#L36-L42
    exportUnset = n: v: if v == null then "unset ${n}" else ''export ${n}="${toString v}"'';
    exportAll = lib.concatMapAttrsStringSep "\n" steamConfigLib.exportUnset;
  };
in
steamConfigLib
