{
  lib,
  enabledApps,
  enabledNonSteamApps,
  allApps,
}:
let
  namedApps =
    lib.mapAttrsToList (name: app: {
      name = "apps.${name}";
      inherit app;
    }) enabledApps
    ++ lib.mapAttrsToList (name: app: {
      name = "nonSteamApps.${name}";
      inherit app;
    }) enabledNonSteamApps;

  duplicateIds = lib.filterAttrs (_: entries: lib.length entries > 1) (
    builtins.groupBy (entry: toString entry.app.id) namedApps
  );

  duplicateMessages = lib.mapAttrsToList (
    id: entries: "id ${id} is used by: ${lib.concatMapStringsSep ", " (e: e.name) entries}"
  ) duplicateIds;

  enabledFileEntries = lib.filter (e: e.entry.enable) (
    lib.concatLists (
      lib.mapAttrsToList (
        appName: app:
        lib.concatMap
          (
            location:
            lib.mapAttrsToList (path: entry: {
              inherit
                appName
                location
                path
                entry
                ;
            }) app.files.${location}.place
          )
          [
            "game"
            "prefix"
          ]
      ) enabledApps
    )
  );

  removeEntries = lib.concatLists (
    lib.mapAttrsToList (
      appName: app:
      lib.concatMap
        (location: map (target: { inherit appName location target; }) app.files.${location}.remove)
        [
          "game"
          "prefix"
        ]
    ) enabledApps
  );

  enabledPatchEntries = lib.filter (e: e.entry.enable) (
    lib.concatLists (
      lib.mapAttrsToList (
        appName: app:
        lib.concatMap
          (
            location:
            lib.mapAttrsToList (path: entry: {
              inherit
                appName
                location
                path
                entry
                ;
            }) app.files.${location}.patch
          )
          [
            "game"
            "prefix"
          ]
      ) enabledApps
    )
  );

  unsafePath = p: p == "" || lib.hasPrefix "/" p || lib.elem ".." (lib.splitString "/" p);

  # "cfg//x.ini" and "./cfg/x.ini" are one file, so they have to compare equal
  normalise =
    p: lib.concatStringsSep "/" (lib.filter (part: part != "" && part != ".") (lib.splitString "/" p));

  # every entry that resolves to a file, so two of anything on one file can be caught together
  targetedEntries =
    map (e: {
      inherit (e) appName location;
      target = normalise e.entry.target;
      declared = e.entry.target;
      op = "place";
    }) enabledFileEntries
    ++ map (e: {
      inherit (e) appName location;
      target = normalise e.entry.target;
      declared = e.entry.target;
      op = "patch";
    }) enabledPatchEntries;

  collisions = lib.filter (group: lib.length group > 1) (
    builtins.attrValues (
      builtins.groupBy (e: "${e.appName}\n${e.location}\n${e.target}") targetedEntries
    )
  );

  # place and patch on the same resolved file are mutually exclusive
  placePatchCollisions = lib.filter (
    group: (lib.any (e: e.op == "place") group) && (lib.any (e: e.op == "patch") group)
  ) collisions;

  duplicateTargets = lib.filter (
    group: lib.all (e: e.op == (builtins.head group).op) group
  ) collisions;

  duplicateTargetMessages = map (
    group:
    let
      e = builtins.head group;
    in
    ''apps.${e.appName}.files.${e.location}.${e.op} has multiple entries targeting "${e.declared}"''
  ) duplicateTargets;

  placePatchMessages = map (
    group:
    let
      e = builtins.head group;
    in
    ''apps.${e.appName}.files.${e.location} both places and patches "${e.target}"''
  ) placePatchCollisions;

  duplicateUnitNames = lib.filterAttrs (_: entries: lib.length entries > 1) (
    builtins.groupBy (entry: entry.app.systemd.target.name) (
      lib.filter (entry: entry.app.systemd.enable) namedApps
    )
  );

  duplicateUnitNameMessages = lib.mapAttrsToList (
    unitName: entries:
    "systemd.target.name ${unitName} is used by: ${lib.concatMapStringsSep ", " (e: e.name) entries}"
  ) duplicateUnitNames;
in
[
  {
    assertion = duplicateIds == { };
    message = "steam-config-nix: multiple apps configured with the same id\n${lib.concatStringsSep "\n" duplicateMessages}";
  }
]
++ lib.concatMap (app: app.assertions) allApps
++ map (e: {
  assertion = (e.entry.source != null) != (e.entry.text != null);
  message = ''steam-config-nix: apps.${e.appName}.files.${e.location}.place."${e.path}" must set exactly one of `source` or `text`'';
}) enabledFileEntries
++ map (e: {
  assertion = !unsafePath e.entry.target;
  message = ''steam-config-nix: apps.${e.appName}.files.${e.location}.place."${e.path}" has an unsafe target "${e.entry.target}" (paths must be relative and must not contain ..)'';
}) enabledFileEntries
++ map (e: {
  assertion = !unsafePath e.target;
  message = ''steam-config-nix: apps.${e.appName}.files.${e.location}.remove has an unsafe path "${e.target}" (paths must be relative and must not contain ..)'';
}) removeEntries
++ map (e: {
  assertion = !unsafePath e.entry.target;
  message = ''steam-config-nix: apps.${e.appName}.files.${e.location}.patch."${e.path}" has an unsafe target "${e.entry.target}" (paths must be relative and must not contain ..)'';
}) enabledPatchEntries
++ [
  {
    assertion = placePatchCollisions == [ ];
    message = "steam-config-nix: a file is both placed and patched\n${lib.concatStringsSep "\n" placePatchMessages}";
  }
]
++ [
  {
    assertion = duplicateTargets == [ ];
    message = "steam-config-nix: multiple file entries resolve to the same target\n${lib.concatStringsSep "\n" duplicateTargetMessages}";
  }
]
++ [
  {
    assertion = duplicateUnitNames == { };
    message = "steam-config-nix: multiple apps configured with the same systemd.target.name\n${lib.concatStringsSep "\n" duplicateUnitNameMessages}";
  }
]
