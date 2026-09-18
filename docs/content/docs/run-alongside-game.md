---
title: Run a tool alongside a game with systemd
weight: 31
---

An app can publish a systemd user target that is active while it runs:

```nix
{
  programs.steam.config.apps."438100" = {
    name = "VRChat";
    systemd.enable = true;
  };

  systemd.user.services.opentrack = {
    partOf = [ "steam-app-vrchat.target" ];
    serviceConfig.ExecStart = lib.getExe pkgs.opentrack;
    wantedBy = [ "steam-app-vrchat.target" ];
  };
}
```

`wantedBy` will start the service when the app launches, and `partOf` will stop
it when the app exits. Under Home Manager these are `Install.WantedBy`,
`Unit.PartOf` and `Service.ExecStart`.

## The two targets

- `steam-app-<name>.target` is active while that app runs. The name comes from
  `systemd.target.name`, which defaults to the app's `name` lowercased, with
  runs of other characters replaced by `-`. "Elden Ring" becomes `elden-ring`.
- `steam-app.target` is active while _any_ app with `systemd.enable` runs. Use
  it for things that should run during any game, like pausing a sync daemon.

Neither can be started or stopped by hand.

To avoid hardcoding the target name, read it from the config:

```nix
{
  programs.steam.config.apps."438100".systemd.enable = true;

  systemd.user.services.opentrack.wantedBy = [
    config.programs.steam.config.apps."438100".systemd.target.unitName
  ];
}
```

## Making the game wait for the tool

Units start alongside the app. To make the app wait until yours is up, also
order it before the target:

```nix
{
  programs.steam.config.apps."438100".systemd.enable = true;

  systemd.user.services.opentrack =
    let
      target = config.programs.steam.config.apps."438100".systemd.target.unitName;
    in
    {
      wantedBy = [ target ];
      before = [ target ];
    };
}
```

The launch will wait until systemd considers the service started, which for the
default `Type=simple` is as soon as it has been forked.

## Running something after the game exits

```nix
{
  programs.steam.config.apps."438100".systemd = {
    enable = true;
    scope.properties.OnSuccess = "sync-saves.service";
  };
}
```

This will fire whenever the app ends, including a crash or stopping it from
Steam. `OnFailure` will never trigger.

## Limits

- A unit that is `partOf` two apps' targets will be stopped when either app
  exits, even if you started it by hand.
- Only user units can be tied to these targets, a NixOS system service cannot.
- Changing `systemd.target.name` will silently stop units that hook the old name
  from starting.
- With no systemd user manager the app still launches, without a scope, and the
  targets are not activated.

## Resource control

The same scope is where CPU, memory and slice limits go. See [Limit a game's
resources with systemd]({{< relref "/docs/resource-control" >}}).
