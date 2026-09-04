---
title: Use a custom Proton build
weight: 14
---

Proton is Valve's compatibility layer for running Windows games. Community
builds such as [Proton-GE](https://github.com/GloriousEggroll/proton-ge-custom)
and proton-cachyos carry extra patches and codecs that fix specific games.

`compatTool` takes either the internal name of a tool Steam already knows about,
or a package:

```nix
{
  programs.steam.config = {
    defaultCompatTool = "proton_experimental";

    apps."1091500" = {
      name = "Cyberpunk 2077";
      compatTool = pkgs.proton-ge-bin;
    };
  };
}
```

`defaultCompatTool` sets Steam's global default. It does not change the module
defaults for individual apps.

## Builds that are not in nixpkgs

Anything containing a `compatibilitytool.vdf`, either at its root or under
`bin/`, works, so a release archive can be used directly:

```nix
{
  programs.steam.config.apps."1091500" = {
    name = "Cyberpunk 2077";
    compatTool = pkgs.fetchzip {
      url = "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton10-10/GE-Proton10-10.tar.gz";
      hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    };
  };
}
```

Replace the hash with the real one. Nix will tell you what it should be on the
first build.

## Caveats

Some unusual custom builds are not compatible with protontricks, so
[Winetricks]({{< relref "/docs/winetricks" >}}) verbs will fail to apply on
them. The failure is harmless and the game still launches.

Switching an app's Proton build does not reset its prefix. If a game breaks
after a switch, deleting the prefix and letting it regenerate is usually the
fix.
