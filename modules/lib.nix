lib:
let
  steamConfigLib = {
    # modified from home-manager lib.shell.exportAll
    # https://github.com/nix-community/home-manager/blob/89c9508bbe9b40d36b3dc206c2483ef176f15173/modules/lib/shell.nix#L36-L42
    exportUnset = n: v: if v == null then "unset ${n}" else ''export ${n}="${toString v}"'';
    exportAll = lib.concatMapAttrsStringSep "\n" steamConfigLib.exportUnset;

    # get a SteamID3 from a SteamID64
    # https://gist.github.com/bcahue/4eae86ae1d10364bb66d
    toSteamId3 =
      userId:
      let
        steamId64Ident = 76561197960265728;
        isSteam64 = userId >= steamId64Ident;
      in
      if isSteam64 then toString (userId - steamId64Ident) else userId;
  };
in
steamConfigLib
