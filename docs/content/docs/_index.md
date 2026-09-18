---
title: Getting started
weight: 1
breadcrumbs: false
sidebar:
  open: true
# the page shipped at this path, so the published link keeps working
aliases:
  - /docs/getting-started/
---

## Add the module

`steam-config-nix` is a flake, providing both a NixOS module and a
[Home Manager](https://github.com/nix-community/home-manager) one.

```nix {eval=false}
steam-config-nix = {
  url = "github:different-name/steam-config-nix";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Import whichever matches how you manage your system:

```nix {eval=false}
# NixOS
imports = [ inputs.steam-config-nix.nixosModules.default ];
```

```nix {eval=false}
# Home Manager
imports = [ inputs.steam-config-nix.homeModules.default ];
```

## Configure a game

Pick a game you have installed and find its App ID: open its store page and read
the number out of the URL. `store.steampowered.com/app/438100/` is App ID
`438100`.

{{< callout type="warning" >}} Most options make use of a wrapper script, so in
most cases anything set manually in Steam's launch options field will be
overwritten. Move launch strings you want to keep into `rawLaunchOptions` before
your first rebuild. {{< /callout >}}

`args` appends arguments to the game's command, and `env` sets environment
variables for it. Cap the framerate, and turn on an overlay so you can see the
cap working:

```nix
{
  programs.steam.config = {
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
desktop entry, the systemd target name, and the wrapper's own messages.

The overlay needs MangoHud installed system-wide: add `pkgs.mangohud` to your
packages if it is not there already.

Rebuild to apply the new configuration.

## Close Steam to apply it

If Steam was running during the rebuild, nothing has changed yet.

Steam keeps its configuration in files it holds open and rewrites when it exits.
Anything written underneath it is discarded. So by default the module waits: it
writes your changes the next time Steam is closed.

Close Steam, open it again and launch the game. The overlay should show the
framerate pinned at 60.

If waiting is not what you want, then:

```nix
{
  programs.steam.config.onSteamRunning = "close";
}
```

That will close Steam during a rebuild, after any running game exits. [How
changes are applied]({{< relref "/docs/applying-changes" >}}) covers the other
choices.

## Change it again

Now edit the same option, and leave Steam running this time:

```nix
{
  programs.steam.config.apps."438100" = {
    name = "VRChat";
    args = [ "--fps=30" ];
    env.MANGOHUD = "1";
  };
}
```

Rebuild without closing Steam, and launch the game. The overlay will show 30
fps.

Steam only has to be told where the wrapper is once, so this change did not
wait. See [How launch options work]({{< relref "/docs/launch-options" >}}).

## Where to go next

- [MangoHud]({{< relref "/docs/mangohud" >}}), [a custom Proton
  build]({{< relref "/docs/proton" >}}) or [a non-Steam
  game]({{< relref "/docs/non-steam-game" >}}).
- The [options search]({{< search-url >}}) for everything the module exposes.
