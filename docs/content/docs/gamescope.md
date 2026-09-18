---
title: Run a game with Gamescope
weight: 11
---

[Gamescope](https://github.com/ValveSoftware/gamescope) is a nested Wayland
compositor. It gives a game its own display server, which handles resolution,
scaling, frame limiting and HDR.

Add it as a wrapper, listed first, with its own flags ended by `--`:

```nix
{
  programs.steam.config.apps."1245620" = {
    name = "Elden Ring";
    wrappers = [
      (lib.getExe pkgs.gamescope)
      "-W" "2560"   # output width
      "-H" "1440"   # output height
      "-r" "144"    # game frame rate
      "-f"          # fullscreen
      "--"
    ];
  };
}
```

Set the resolution and frame rate to match your display.

## The `--` separator

Everything before `--` is gamescope's, everything after runs inside its session.
Without it, gamescope will try to read the game's command as its own flags.

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

That runs GameMode inside gamescope.
