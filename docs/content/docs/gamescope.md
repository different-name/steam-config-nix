---
title: Run a game with Gamescope
weight: 11
---

[Gamescope](https://github.com/ValveSoftware/gamescope) is a nested Wayland
compositor. It gives a game its own display server, which is how the Steam Deck
handles resolution, scaling, framerate limiting and HDR without the game
knowing.

There is no gamescope option. You set it up as an ordinary wrapper, listed
first, with its own flags terminated by `--`:

```nix
{
  programs.steam.config.apps."1245620" = {
    name = "Elden Ring";
    wrappers = [
      (lib.getExe pkgs.gamescope)
      "-W" "2560"   # output width
      "-H" "1440"   # output height
      "-r" "144"    # refresh rate
      "-f"          # fullscreen
      "--"
    ];
  };
}
```

Set the resolution and refresh rate to your own display.

## The `--` matters

Everything before `--` is gamescope's, everything after runs inside its session.
Forgetting it means gamescope tries to interpret the game's command as its own
flags.

## Combining with other wrappers

Order is outermost first, so keep gamescope at the front and put anything that
should run inside the session after the `--`:

```nix
{
  programs.steam.config.apps."1245620" = {
    name = "Elden Ring";
    wrappers = [
      (lib.getExe pkgs.gamescope)
      "-f"
      "--"
      "gamemoderun"
    ];
  };
}
```

That runs GameMode inside gamescope. Reversing them runs gamescope inside
GameMode, which is usually not what you want.
