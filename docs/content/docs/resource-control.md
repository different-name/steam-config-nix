---
title: Limit a game's resources with systemd
weight: 32
---

With `systemd.enable`, an app runs inside a transient systemd scope, which puts
the game and everything it spawns in one cgroup. `systemd.scope.properties` sets
properties on that scope, passed through to `systemd-run --property`:

```nix
{
  programs.steam.config.apps."438100" = {
    name = "VRChat";
    systemd.enable = true;
    systemd.scope.properties = {
      Slice = "games.slice";
      CPUWeight = 200;
    };
  };
}
```

See `systemd.resource-control(5)` for the properties and their values.

## Slices

Without `Slice` the scope lands under `app.slice` rather than inheriting the
cgroup Steam was launched in.

A slice sets limits once for every game in it:

```nix
{
  systemd.user.slices.games.sliceConfig = {
    CPUWeight = 50;
    MemoryHigh = "12G";
  };
}
```

Then point each app at it with `Slice = "games.slice"`. Limits on the slice
apply to everything in it together, so two games running at once will share
them.

## Limits

- The scope is named `app-steam-<id>-<random>.scope`, where `<id>` is
  `steamRunId`, so there is no fixed name to stop an app by. Match
  `app-steam-<id>-*` instead.
- Output is not captured by the journal. The scope inherits Steam's stdout and
  stderr.
- Setting `Wants` in `systemd.scope.properties` will stop the target from
  starting, and setting `After` will stop the launch from waiting for it. Put
  dependencies on the target instead, see [Run a tool alongside a game with
  systemd]({{< relref "/docs/run-alongside-game" >}}).
- With no systemd user manager the app still launches, without a scope, so no
  limits are applied.
