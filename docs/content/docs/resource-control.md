---
title: Limit a game's resources with systemd
weight: 32
---

A managed app runs inside a transient systemd scope, which puts the game and
everything it spawns in one cgroup. `systemd.scope.properties` sets properties
on that scope, passed through to `systemd-run --property`:

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

`systemd.enable` is what creates the scope, so it has to be on for any of this
to apply.

Any property a scope accepts works, so `CPUWeight`, `MemoryMax`, `MemoryHigh`
and `AllowedCPUs` are all available. See `systemd.resource-control(5)` for the
full set and what the values mean.

## Why a slice

Without `Slice` the scope lands under `app.slice` rather than inheriting the
cgroup Steam was launched in.

Naming a slice gives you one place to set limits for every game, instead of
repeating them per app:

```nix
{
  systemd.user.slices.games.sliceConfig = {
    CPUWeight = 50;
    MemoryHigh = "12G";
  };
}
```

Then point each app at it with `Slice = "games.slice"`. Limits on the slice
apply to everything in it together, so two games running at once share the
budget rather than getting one each.

## Limits

- The scope is named `app-steam-<id>-<random>.scope`, where `<id>` is
  `steamRunId`, so there is no fixed name to stop an app by. Match
  `app-steam-<id>-*` instead.
- Output is not captured by the journal. The scope inherits Steam's stdout and
  stderr.
- Put dependencies on the target, not in `systemd.scope.properties`. The scope
  accepts them, but its name is not stable. See [Run a tool alongside a game
  with systemd]({{< relref "/docs/run-alongside-game" >}}).
- With no systemd user manager the app still launches, without a scope, so no
  limits are applied.
