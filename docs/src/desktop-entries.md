# Desktop Entries

Any app can generate a desktop entry that launches it through Steam, so your application launcher can start it directly:

```nix
{
  programs.steam.config.apps."Cyberpunk 2077" = {
    id = 1091500;
    # name, comment, icon and categories all have sensible defaults
    desktopEntry.enable = true;
  };
}
```

This works for non-Steam apps too, where the name and icon default to the app's own `name` and `icon`.

For Steam apps, the entry can use the app's own icon from your Steam library instead of the generic Steam icon. This is controlled globally by `desktopEntries.libraryIcons` (on by default) and per-app by `desktopEntry.useLibraryIcon`. Setting `desktopEntry.icon` explicitly always takes precedence. Library icons come from Steam's local cache, so an app must have been seen by Steam at least once for its icon to be available, and they fall back to the Steam icon when they cannot be resolved.
