{
  lib,
  enabledApps,
  enabledNonSteamApps,
}:
let
  allApps = lib.attrValues enabledApps ++ lib.attrValues enabledNonSteamApps;

  duplicates =
    items:
    lib.attrNames (
      lib.filterAttrs (_: n: n > 1) (
        lib.foldl' (acc: k: acc // { ${k} = (acc.${k} or 0) + 1; }) { } items
      )
    );

  duplicateIds = duplicates (map (app: toString app.id) allApps);
  duplicateKeys = duplicates (map (app: app.appKey) allApps);
  emptyKeys = lib.attrNames (lib.filterAttrs (_: app: app.key == "") enabledNonSteamApps);
  duplicateTargets = duplicates (
    map (app: app.systemd.target.name) (lib.filter (app: app.systemd.enable) allApps)
  );
  badTargets = lib.filter (
    app: app.systemd.enable && lib.match "[a-z0-9-]+" app.systemd.target.name == null
  ) allApps;
in
[
  {
    assertion = duplicateIds == [ ];
    message = "programs.steam-config: app ID used more than once across apps and nonSteamApps: ${lib.concatStringsSep ", " duplicateIds}";
  }
  {
    assertion = duplicateKeys == [ ];
    message = "programs.steam-config: more than one app has the key ${lib.concatStringsSep ", " duplicateKeys}. A Steam app's key is its ID and a non-Steam app's is its attribute name lowercased with `-` for anything outside a-z0-9, so a non-Steam name that only differs outside a-z0-9 or equals a Steam app ID needs a different name.";
  }
  {
    assertion = emptyKeys == [ ];
    message = "programs.steam-config.nonSteamApps: an attribute name needs at least one letter or digit in a-z0-9: ${lib.concatStringsSep ", " emptyKeys}";
  }
  {
    assertion = duplicateTargets == [ ];
    message = "programs.steam-config: systemd target name used more than once: ${lib.concatStringsSep ", " duplicateTargets}";
  }
  {
    assertion = badTargets == [ ];
    message = "programs.steam-config: systemd.target.name must be lowercase letters, digits and dashes: ${
      lib.concatStringsSep ", " (map (app: app.systemd.target.name) badTargets)
    }";
  }
]
