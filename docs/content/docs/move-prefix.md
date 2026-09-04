---
title: Move a Proton prefix to another disk
weight: 35
---

Proton keeps a prefix beside the game, in `steamapps/compatdata/<id>`. Prefixes
grow, and there is no reason they have to live on the same drive as the library.

```nix
{
  programs.steam.config.apps."1091500" = {
    name = "Cyberpunk 2077";
    prefixPath = "/mnt/games/prefixes/cyberpunk";
  };
}
```

The directory is created at launch if missing. Its _parent_ is never created, so
if you point this at a drive that is not mounted, the launch fails with an error
rather than writing into the empty mount point and hiding the drive behind it.

Prefix-aware options follow the move: `winetricks` verbs and `files.prefix`
entries are applied to the new location, not the leftover directory in the
library.

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

Setting it through `rawLaunchOptions` is **not** equivalent. It is applied too
late for anything to read, so the prefix moves but `winetricks` and
`files.prefix` keep using the old path.

## What still points at the old location

Steam creates an empty `steamapps/compatdata/<id>` regardless, and any tool that
looks a prefix up by app ID finds that one. Running `protontricks` by hand will
experience this issue, so point it at the real path explicitly.

The prefix also has to be reachable from inside the Steam runtime container.
Paths under your home directory work. `/tmp` does not, because the container has
its own.

Applying winetricks verbs to a relocated prefix runs protontricks inside a bind
mount, which needs unprivileged user namespaces. Where those are unavailable the
verbs are not applied and the game still launches.
