{ lib }:
# a path inside the store is copied so the generated file keeps a reference to it
v: if lib.isPath v && lib.hasPrefix builtins.storeDir (toString v) then "${v}" else toString v
