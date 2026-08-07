# Non-Steam Apps

Add non-Steam games and applications as Steam shortcuts, so they show up in your library and can use compatibility tools, launch options and artwork like any other app:

```nix
{
  programs.steam.config.nonSteamApps."Vintage Story" = {
    # target is the executable, a package or an absolute path
    target = pkgs.vintagestory;
    compatTool = "proton_experimental";
    launchOptions.env.MANGOHUD = "1";
    artwork.icon = ./vintagestory.png;
  };
}
```

Non-Steam apps share the common per-app options with Steam apps: `compatTool`, `launchOptions` / `launchOptionsStr`, `winetricks`, `desktopEntry` and `artwork`. On top of those they have:

- `target`: the executable to launch, given as a package (resolved with `lib.getExe`) or an absolute path.
- `name`: the name shown in Steam, defaulting to the attribute name.
- `startIn`: the working directory, defaulting to the directory of `target`.
- `isHidden`, `allowOverlay`, `inVrLibrary`: the usual Steam shortcut toggles.
- `artwork.icon`: the shortcut's icon. Unlike Steam apps, non-Steam apps can set this, since Steam does not manage their icons.

## App IDs

Steam identifies a shortcut by a numeric ID. By default it is derived from a `seed` (which defaults to the app's name), so it stays stable across rebuilds without you tracking a number.

Because the ID feeds the Proton prefix path, changing it (by renaming the app or setting a different `seed` or `id`) creates a fresh Wine prefix. Set an explicit `seed` if you want to rename the app without losing its prefix.

Note that `files`, `removeFiles` and the [Steam app settings](./app-settings.md) (`betaBranch`, `language`, `updateBehavior`) apply to Steam apps only.
