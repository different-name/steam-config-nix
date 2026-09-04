---
title: Run a tool alongside a game with systemd
weight: 31
---

Plenty of tools only make sense while a specific game is open (an OSC bridge, a
controller daemon, a recording script) and should stop when it closes.

An app can publish a systemd user target that is active exactly while it runs,
so ordinary systemd wiring does the rest:

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

`wantedBy` starts the service when the app launches, `partOf` stops it when the
app exits. None of that is specific to this module, it is the same wiring you
would use with `graphical-session.target`. Under Home Manager the same unit is
written with its own spelling: `Install.WantedBy`, `Unit.PartOf` and
`Service.ExecStart`.

## The two targets

- `steam-app-<name>.target` is active while that app runs. The name comes from
  `systemd.target.name`, which defaults to the app's `name` lowercased, with
  runs of other characters replaced by `-`. "Elden Ring" becomes `elden-ring`.
- `steam-app.target` is active while _any_ app with `systemd.enable` runs. Use
  it for things that should run during any game, like pausing a sync daemon.

`steam-app.target` stops when the last app exits, so it stays up if you have two
games open and close one.

Both refuse to be started by hand. They are activated by an app launching and
nothing else.

To avoid writing and maintaining the target name by hand, read it from the
config:

```nix
{
  programs.steam.config.apps."438100".systemd.enable = true;

  systemd.user.services.osc-bridge.wantedBy = [
    config.programs.steam.config.apps."438100".systemd.target.unitName
  ];
}
```

## Making the game wait for the tool

Units start alongside the app. To make the app wait until yours is up, order it
before the target:

```nix
{
  programs.steam.config.apps."438100".systemd.enable = true;

  systemd.user.services.osc-bridge.before = [
    config.programs.steam.config.apps."438100".systemd.target.unitName
  ];
}
```

A service that is slow to start delays the launch by exactly that much.

## Running something after the game exits

```nix
{
  programs.steam.config.apps."438100".systemd.scope.properties.OnSuccess = "sync-saves.service";
}
```

This fires whenever the app ends, including a crash or stopping it from Steam.
`OnFailure` never triggers, because a scope's result does not follow the exit
status of the processes inside it.

## Limits

- Stopping does not count references. A unit started by hand, or wanted by two
  apps at once, is stopped when _either_ app exits.
- Only user units can be tied to these targets, a NixOS system service cannot.
- Changing `systemd.target.name` silently orphans units that hook the old name.
- With no systemd user manager the app still launches, without a scope, and the
  targets are not activated.

## Resource control

The same scope is where CPU, memory and slice limits go. See [Limit a game's
resources with systemd]({{< relref "/docs/resource-control" >}}).
