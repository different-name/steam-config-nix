---
title: Show a performance overlay with MangoHud
weight: 12
---

[MangoHud](https://github.com/flightlessmango/MangoHud) draws an FPS and system
metrics overlay on Vulkan and OpenGL games.

The simplest form is an environment variable, which works when MangoHud is
installed system-wide:

```nix
{
  programs.steam.config.apps."1091500" = {
    name = "Cyberpunk 2077";
    env.MANGOHUD = "1";
  };
}
```

If you would rather not install it globally, run it as a wrapper instead and the
package comes from nixpkgs:

```nix
{
  programs.steam.config.apps."1091500" = {
    name = "Cyberpunk 2077";
    wrappers = [ pkgs.mangohud ];
  };
}
```

## Configuring it

MangoHud reads a config file rather than taking options through Steam. Point it
at one with `MANGOHUD_CONFIG` for inline settings, or manage a config file
declaratively with `home.file`. It lives under your home directory, not in the
game, so it is not something this module places.

## Turning it on for every game

Set the variable once in Steam's own environment rather than per app. See [Set
environment variables for every game]({{< relref "/docs/all-games-env" >}}).
