---
title: Add a desktop entry for a game
weight: 36
---

A desktop entry makes an app appear in rofi, wofi, your DE's menu or anywhere
else that reads `.desktop` files, and launching it goes through Steam as normal.

```nix
{
  programs.steam.config.apps."1091500" = {
    name = "Cyberpunk 2077";
    desktopEntry.enable = true;
  };
}
```

Name, comment, icon and categories all have defaults, so that is usually the
whole configuration. The name comes from the app's own `name`, which for a Steam
app defaults to its ID, so set `name` if you want a readable entry. It works for
non-Steam apps too, where the name and icon come from `name` and `artwork.icon`.

## For every app at once

```nix
{
  programs.steam.config.desktopEntries.enable = true;
}
```

Each app can still opt out with `desktopEntry.enable = false`.

## Icons

By default a Steam app's entry uses the app's own icon from your library rather
than the generic Steam one. Those come from Steam's local cache, so an app has
to have been seen by Steam at least once for its icon to exist. When it cannot
be resolved the entry falls back to the Steam icon.

Setting `desktopEntry.icon` explicitly always wins.
