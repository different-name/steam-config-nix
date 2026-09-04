---
title: VRChat
weight: 41
---

VRChat is a Unity game with a few well-known Linux quirks and an unusually large
ecosystem of companion tools.

## Unset TZ

```nix
{
  programs.steam.config.apps."438100" = {
    name = "VRChat";
    env.TZ = null;
  };
}
```

VRChat's Unity build mishandles a set `TZ`. `null` unsets a variable rather than
setting it to an empty string.

## Companion tools that follow the game

OSC bridges, tracking daemons and overlays should run while VRChat runs and stop
when it stops:

```nix
{
  programs.steam.config.apps."438100" = {
    name = "VRChat";
    systemd.enable = true;
  };

  systemd.user.services.osc-bridge = {
    partOf = [ "steam-app-vrchat.target" ];
    serviceConfig.ExecStart = lib.getExe pkgs.opentrack;
    wantedBy = [ "steam-app-vrchat.target" ];
  };
}
```

See [Run a tool alongside a game with
systemd]({{< relref "/docs/run-alongside-game" >}}) for ordering, resource
control and the limits.

## Settings in the prefix

VRChat keeps its own settings as Unity PlayerPrefs in the prefix registry. See
[Patch a Unity game's settings]({{< relref "/docs/unity" >}}).

## Video playback

Video players in worlds rely on a `yt-dlp` helper, which is a common source of
breakage on Linux.
[vrchat-video-resolver](https://github.com/different-name/vrchat-video-resolver)
repairs it, and is a separate module that builds on this one. See [Third party
modules]({{< relref "/docs/third-party-modules" >}}).
