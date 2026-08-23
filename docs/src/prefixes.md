# Proton Prefixes

By default Proton keeps an app's prefix in the Steam library, at `steamapps/compatdata/<id>`. Set `prefixPath` to keep it somewhere else, such as a larger or faster drive:

```nix
{
  programs.steam.config.apps."1091500" = {
    name = "Cyberpunk 2077";
    prefixPath = "/mnt/games/prefixes/cyberpunk";
  };
}
```

The directory is created at launch if it is missing. Its parent is never created: if you point `prefixPath` at a drive that is not mounted yet, the launch fails with an error instead of writing to the mount point and hiding the drive behind it.

Prefix aware options follow the new location, so [`winetricks`](./winetricks.md) verbs and [`files.prefix`](./files.md) entries are applied to the relocated prefix rather than the empty directory left in the library.

## Setting the variable directly

Proton reads the prefix location from `STEAM_COMPAT_DATA_PATH`, so setting that in `env` relocates the prefix too, and `prefixPath` defaults to it:

```nix
{
  # these are equivalent
  prefixPath = "/mnt/games/prefixes/cyberpunk";
  env.STEAM_COMPAT_DATA_PATH = "/mnt/games/prefixes/cyberpunk";
}
```

Setting it through `rawLaunchOptions` does not work the same way. The variable is applied too late for anything to read it, so the prefix moves but `winetricks` and `files.prefix` keep using the old location.

## Limitations

Steam still creates an empty `steamapps/compatdata/<id>` for the app, and other tools that look a prefix up by app ID will find that directory rather than the relocated one. Running `protontricks` by hand is the common case.

The prefix must also be somewhere the Steam runtime container can reach. Paths under your home directory work; `/tmp` does not, because the container has its own.

Applying `winetricks` verbs to a relocated prefix runs protontricks inside a bind mount, which needs unprivileged user namespaces. Where those are unavailable the verbs are not applied, and the game still launches.
