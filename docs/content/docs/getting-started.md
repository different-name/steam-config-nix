---
title: Getting started
weight: 1
breadcrumbs: false
aliases:
  - /docs/
---

## Add the module

The `steam-config-nix` flake provides both NixOS and
[Home Manager](https://github.com/nix-community/home-manager) modules.

Add the flake to your inputs:

```nix {eval=false}
steam-config-nix = {
  url = "github:different-name/steam-config-nix";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

And import the corresponding module:

```nix {eval=false}
# NixOS
imports = [ inputs.steam-config-nix.nixosModules.default ];
programs.steam.enable = true;
```

```nix {eval=false}
# Home Manager
imports = [ inputs.steam-config-nix.homeModules.default ];
```

## Configure a game

Pick a game you have installed and find its App ID: open its store page and read
the number out of the URL. `store.steampowered.com/app/438100/` is App ID
`438100`.

`args` appends arguments to the game's command, and `env` sets environment
variables for it. Cap the framerate, and turn on an overlay so you can see the
cap working:

```nix
{
  programs.steam-config = {
    enable = true;

    apps."438100" = {
      name = "VRChat";
      args = [ "--fps=60" ];
      env.MANGOHUD = "1";
    };
  };
}
```

`name` is optional and never has to match Steam's own name. It is used for the
desktop entry, the systemd target name and notifications.

The overlay needs MangoHud installed system-wide: add `pkgs.mangohud` to your
packages if it is not there already.

Rebuild to apply the new configuration.

## Restart Steam once

The module installs its own `steam` command, which points Steam at a launch step
that every game runs through. A Steam that was already running during the
rebuild was not started that way, so close it and open it again.

Launch the game. The overlay should show the framerate pinned at 60.

## Change it again

Now edit the same option, and leave Steam running this time:

```nix
{
  programs.steam-config.apps."438100" = {
    name = "VRChat";
    args = [ "--fps=30" ];
    env.MANGOHUD = "1";
  };
}
```

Rebuild without closing Steam, and launch the game. The overlay will show 30
fps. Launch options never touch Steam's own files, so a change to them applies
at the next launch. See [How launch options
work]({{< relref "/docs/launch-options" >}}).

## Settings Steam keeps itself

Compatibility tools, non-Steam shortcuts, betas and the like live in files Steam
rewrites when it exits, so those are written while Steam is closed. By default
the module waits for that. To have it close Steam for you instead:

```nix
{
  programs.steam-config.onSteamRunning = "close";
}
```

[How changes are applied]({{< relref "/docs/applying-changes" >}}) covers the
other choices.

## Where to go next

- [MangoHud]({{< relref "/docs/mangohud" >}}), [a custom Proton
  build]({{< relref "/docs/proton" >}}) or [a non-Steam
  game]({{< relref "/docs/non-steam-game" >}}).
- The [options search]({{< search-url >}}) for everything the module exposes.
