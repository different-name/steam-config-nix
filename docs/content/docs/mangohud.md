---
title: Show a performance overlay with MangoHud
weight: 12
---

[MangoHud](https://github.com/flightlessmango/MangoHud) draws an FPS and system
metrics overlay on Vulkan and OpenGL games.

`MANGOHUD=1` enables it for Vulkan games when MangoHud is installed system-wide:

```nix
{
  programs.steam.config.apps."1091500" = {
    name = "Cyberpunk 2077";
    env.MANGOHUD = "1";
  };
}
```

Without a system-wide install, or for OpenGL games, use it as a wrapper:

```nix
{
  programs.steam.config.apps."1091500" = {
    name = "Cyberpunk 2077";
    wrappers = [ pkgs.mangohud ];
  };
}
```

## Configuring it

Set inline settings with `env.MANGOHUD_CONFIG`, or point
`env.MANGOHUD_CONFIGFILE` at a config file.

## Turning it on for every game

Set the variable once in Steam's own environment rather than per app. See [Set
environment variables for every game]({{< relref "/docs/all-games-env" >}}).
