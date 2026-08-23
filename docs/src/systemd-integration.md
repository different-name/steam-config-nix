# Systemd Integration

> [!NOTE]
> Setting `systemd.enable` overwrites any launch options set manually in Steam. This is because the app is launched by a wrapper script, which is applied using Steam's launch options.

An app can publish a systemd user target that is active while it runs, so units can be started and stopped with the app:

```nix
{
  programs.steam.config.apps."438100" = {
    name = "VRChat";
    systemd.enable = true;
  };

  systemd.user.services.oscleash = {
    Unit.PartOf = [ "steam-app-vrchat.target" ];
    Service.ExecStart = lib.getExe pkgs.oscleash;
    Install.WantedBy = [ "steam-app-vrchat.target" ];
  };
}
```

`WantedBy` starts the service when the app launches, `PartOf` stops it when the app exits. This is the same wiring you would use for `graphical-session.target`, and none of it is specific to this module.

## Targets

Two targets are generated:

- `steam-app-<name>.target` is active while that app runs. The name comes from `systemd.target.name`, which defaults to the app's `name`, lowercased.
- `steam-app.target` is active while any app with `systemd.enable` runs. Use it for units that should run during any game, such as pausing a sync daemon.

`steam-app.target` stops when the last app exits, so it stays active if you have two games open and close one.

Both targets refuse to be started by hand. They are activated by an app launching, and nothing else.

The full unit name is available as `systemd.target.unitName`, if you would rather not repeat the string:

```nix
{
  systemd.user.services.oscleash.Install.WantedBy = [
    config.programs.steam.config.apps."438100".systemd.target.unitName
  ];
}
```

## Ordering

Units start alongside the app. To make the app wait until a unit is up, order the unit before the target:

```nix
{
  systemd.user.services.oscleash.Unit.Before = [ "steam-app-vrchat.target" ];
}
```

The app then does not launch until the service is active, and a service that is slow to start delays the launch by that much.

## Checking whether a game is running

`steam-app.target` answers that for scripts and status bars:

```bash
systemctl --user is-active steam-app.target
```

## Resource control

The app is launched inside a transient scope, and `systemd.scope.properties` sets properties on that scope:

```nix
{
  programs.steam.config.apps."438100".systemd.scope.properties = {
    Slice = "games.slice";
    CPUWeight = 200;
  };
}
```

Without this the scope is placed under `app.slice`, wherever `systemd-run` puts it, rather than inheriting the cgroup Steam was launched in.

## Running something after an app exits

`OnSuccess` activates a unit once the app is gone:

```nix
{
  programs.steam.config.apps."438100".systemd.scope.properties.OnSuccess = "sync-saves.service";
}
```

This runs whenever the app ends, including when it crashes or you stop it from Steam. `OnFailure` is never triggered, because a scope's result does not follow the exit status of the processes inside it.

## Details and limits

- Stopping does not count references. A unit you started by hand, or one wanted by two apps at once, is stopped when either app exits.
- Only user units can be tied to these targets. A NixOS system service cannot be.
- Other configuration refers to the target by name, so changing `systemd.target.name` stops units that hook the old name from starting.
- The scope is named `app-steam-<id>-<random>.scope`, so there is no fixed name to stop an app with. Match `app-steam-<id>-*` instead.
- Output is not captured by the journal. The scope inherits stdout and stderr from Steam.
- `systemd.target.unitConfig` can override what the target sets, including `StopWhenUnneeded` and its dependencies on `steam-app.target`. Overriding those stops the target being torn down when the app exits.
- Dependencies belong on the target rather than in `systemd.scope.properties`. The scope accepts them, but its name is not stable and it is not the unit other configuration should refer to.
- If there is no systemd user manager the app still launches, without a scope, and the targets are not activated.
