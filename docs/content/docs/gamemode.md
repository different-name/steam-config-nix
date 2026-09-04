---
title: Use GameMode
weight: 13
---

[GameMode](https://github.com/FeralInteractive/gamemode) asks the system to
apply a set of performance tweaks (governor, scheduling, GPU performance mode)
for as long as a game runs.

It is a wrapper:

```nix
{
  programs.steam.config.apps."1091500" = {
    name = "Cyberpunk 2077";
    wrappers = [ "gamemoderun" ];
  };
}
```

`"gamemoderun"` is given as a bare name here because the GameMode daemon has to
be enabled system-wide anyway (`programs.gamemode.enable` on NixOS), which puts
it on `PATH`. A package works too if you would rather be explicit.

## Ordering with gamescope

If you also use gamescope, GameMode should run inside it. See [Run a game with
Gamescope]({{< relref "/docs/gamescope" >}}).
