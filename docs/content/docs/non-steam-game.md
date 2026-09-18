---
title: Add a non-Steam game
weight: 34
---

A Steam shortcut lets anything appear in your library and use Steam's
compatibility tools, overlay, controller handling and artwork.

```nix
{
  programs.steam.config.nonSteamApps."Vintage Story" = {
    target = pkgs.vintagestory;   # a package or an absolute path
    env.MANGOHUD = "1";
    artwork.icon = ./vintagestory.png;
  };
}
```

Non-Steam apps take the same per-app options as Steam apps plus a few of their
own:

- `target`: the executable, as a package (resolved with `lib.getExe`) or an
  absolute path
- `startIn`: working directory, defaulting to `target`'s directory
- `isHidden`, `allowOverlay`, `inVrLibrary`: the usual shortcut toggles
- `artwork.icon`: the shortcut's icon

Options that act on a Steam-installed game, such as `files` and `betaBranch`,
are Steam apps only.

## Renaming without losing the prefix

Steam identifies a shortcut by a number. The module derives one from a `seed`
that defaults to the attribute name, so it stays stable across rebuilds, but
**changing the attribute name will give the app a new ID, and with it a new
prefix and no play time.** Changing `name` is safe.

If you want to rename one and keep its prefix, pin the seed to the old attribute
name first:

```nix
{
  programs.steam.config.nonSteamApps."Vintage Story (2025)" = {
    target = pkgs.vintagestory;
    seed = "Vintage Story";  # keep the original ID and prefix
  };
}
```
