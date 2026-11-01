---
title: How launch options work
weight: 4
---

Steam runs every game through a launch shell when the `STEAM_GAME_LAUNCH_SHELL`
variable names one. The `steam` command this module installs sets it, so each
launch goes through `steam-config-launch` first. It applies the app's options
and then runs the command line Steam built. Nothing is written into Steam's
launch options field.

The `steam` on `PATH` is that command. A script, autostart entry or unit that
starts Steam by store path should use `programs.steam-config.launcher`.

## When changes apply

A rebuild places one launch spec per configured app under the module's data
directory. The launch step reads it at the next game launch, so a change to any
launch option applies without closing Steam. Only a Steam that was started
before the module was first enabled has to be restarted once.

## Launch options set in Steam

Whatever is set in Steam's launch options field is kept. Steam folds it into the
command line it builds, and the launch step runs that command line as it is.

## What a launch does

In order:

1. `programs.steam-config.env`, then the app's `env`
2. `WINEDLLOVERRIDES` from `dllOverrides`
3. `prefixPath`, as `STEAM_COMPAT_DATA_PATH`
4. `winetricks` verbs that are not installed yet
5. `preHook`
6. `rawLaunchOptions` spliced into the command line, then `args` appended
7. the systemd scope from `systemd.enable`
8. the files overlay from `files`
9. `wrappers`, outermost first, then the command line in `/bin/sh -c`

`steam-config-launch show <app id>` prints what a launch would do for an app,
with where each environment variable came from, the final command line and the
exec chain, without launching anything. A non-Steam app is named by its
attribute name.

## preHook

`preHook` runs as its own bash before the scope and the files overlay, with the
environment above exported. `cmdline` holds the command line Steam built, also
passed as `$1`, and the `wrappers` and `args` arrays hold the options of the
same name. Edits to the three, exports and unsets all carry into the launch.

A non-zero exit stops the launch with that code and a notification. Exiting
early with `0` also stops the launch, silently, so let the hook run to its end.

## DLL overrides

Wine reads DLL overrides from the single `WINEDLLOVERRIDES` variable.
`dllOverrides` compiles into it, so several modules can each add overrides.
Setting `WINEDLLOVERRIDES` in `env` as well as `dllOverrides` is rejected.

## Raw launch options

`rawLaunchOptions` is the classic single-line Steam string, with `%command%`
standing in for the game:

```nix
{
  programs.steam-config.apps."1234560" = {
    name = "Some Game";
    rawLaunchOptions = "DXVK_ASYNC=1 gamemoderun %command% -vulkan";
  };
}
```

It is spliced into the command line, which runs inside `/bin/sh -c` as the last
link of the chain, with `wrappers` and the files overlay around it and `args`
after it. A string with no `%command%` is appended as arguments, matching
Steam's own behaviour. Where it and `env` set the same variable, the raw string
wins.

Use it to paste a launch string you already have, and the structured options for
anything new.
