{ lib }:
let
  appIdMin = lib.fromHexString "0x80000000";
  appIdMax = lib.fromHexString "0xFFFFFFFF";

  modulo = a: b: a - b * (a / b);
in
{
  inherit appIdMin appIdMax;

  slugify =
    s:
    lib.concatStringsSep "-" (
      lib.filter (part: part != "") (
        lib.splitString "-" (
          lib.stringAsChars (c: if lib.match "[a-z0-9]" c != null then c else "-") (lib.toLower s)
        )
      )
    );

  seedToId =
    seed:
    let
      # fromHexString only supports a max value of 2^63, so this has to be trimmed
      hex = lib.substring 0 15 (lib.hashString "md5" seed);
      base10 = lib.fromHexString hex;
      remainder = modulo base10 (appIdMax - appIdMin + 1);
    in
    remainder + appIdMin;

  # appid << 32 | 0x02000000 exceeds nix's 2^63 int limit, so it is built as a decimal string
  mkShortcutGameId =
    appid:
    let
      shift = 4294967296;
      shortcutFlag = 33554432;
      hi = appid / 1000000;
      lo = appid - hi * 1000000;
      r = lo * shift + shortcutFlag;
      rHi = r / 1000000;
      rLo = r - rHi * 1000000;
      top = hi * shift + rHi;
    in
    "${toString top}${lib.fixedWidthString 6 "0" (toString rLo)}";
}
