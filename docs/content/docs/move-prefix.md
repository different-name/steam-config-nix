---
title: Move a Proton prefix to another disk
weight: 35
---

Proton keeps a prefix beside the game, in `steamapps/compatdata/<id>`.
`prefixPath` moves it:

```nix
{
  programs.steam.config.apps."1091500" = {
    name = "Cyberpunk 2077";
    prefixPath = "/mnt/games/prefixes/cyberpunk";
  };
}
```

The directory will be created at launch, but its parent will not, so the launch
will fail if the parent is missing (an unmounted drive, for example).
`winetricks` verbs and `files.prefix` entries will follow the move.

## Setting the variable instead

Proton reads the location from `STEAM_COMPAT_DATA_PATH`, and `prefixPath`
defaults to whatever `env` sets it to, so these are equivalent:

```nix
{
  programs.steam.config.apps."1091500" = {
    name = "Cyberpunk 2077";
    env.STEAM_COMPAT_DATA_PATH = "/mnt/games/prefixes/cyberpunk";
  };
}
```

Setting it through `rawLaunchOptions` is **not** equivalent. It only reaches the
game command, so the prefix will move but `winetricks` and `files.prefix` will
keep using the old path.

## What still points at the old location

Steam creates an empty `steamapps/compatdata/<id>` regardless, and any tool that
looks a prefix up by app ID, `protontricks` included, will find that one.

The prefix also has to be reachable from inside the Steam runtime container.
Paths under your home directory work. `/tmp` does not, because the container has
its own.

Winetricks verbs for a relocated prefix need unprivileged user namespaces.
Without them the verbs will not be applied, and the game will still launch.
