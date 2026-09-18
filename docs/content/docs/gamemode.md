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

The GameMode daemon has to be enabled system-wide (`programs.gamemode.enable` on
NixOS), which puts `gamemoderun` on `PATH`. `pkgs.gamemode` works too.

## With gamescope

For ordering with gamescope, see [Run a game with
Gamescope]({{< relref "/docs/gamescope" >}}).
