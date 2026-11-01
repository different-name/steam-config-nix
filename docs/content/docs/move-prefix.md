---
title: Move a Proton prefix to another disk
weight: 35
---

Proton keeps a prefix beside the game, in `steamapps/compatdata/<id>`.
`prefixPath` moves it:

```nix
{
  programs.steam-config.apps."1091500" = {
    name = "Cyberpunk 2077";
    prefixPath = "/mnt/games/prefixes/cyberpunk";
  };
}
```

The directory is created at launch, but its parent is not, so the launch stops
with a notification if the parent is missing (an unmounted drive, for example).
`winetricks` verbs and `files.prefix` entries follow the move.

## Setting the variable instead

Proton reads the location from `STEAM_COMPAT_DATA_PATH`, so setting it in `env`
also moves the prefix:

```nix
{
  programs.steam-config.apps."1091500" = {
    name = "Cyberpunk 2077";
    env.STEAM_COMPAT_DATA_PATH = "/mnt/games/prefixes/cyberpunk";
  };
}
```

`files.prefix` follows it, but `winetricks` verbs do not, and the directory is
not created for you. Setting it through `rawLaunchOptions` only reaches the game
command, so neither follows.

## What still points at the old location

Steam creates an empty `steamapps/compatdata/<id>` regardless, and any tool that
looks a prefix up by app ID, `protontricks` included, will find that one. The
launch step binds the moved prefix over it while winetricks verbs install, which
needs unprivileged user namespaces.

The prefix also has to be reachable from inside the Steam runtime container.
Paths under your home directory work. `/tmp` does not, because the container has
its own.
