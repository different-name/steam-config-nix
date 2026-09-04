---
title: How launch options work
weight: 4
---

Steam gives each app a single launch options string. The module does not write
your configuration into it. Instead it compiles everything into a wrapper script
at a stable path outside Steam, and puts only this into Steam:

```
<wrapper> %command%
```

## What it buys

Steam's launch options field is written **once**, when the path first changes.
That write lands in Steam's own configuration, so it waits for Steam to close
like anything else there. After it, editing your configuration rewrites the
script rather than Steam's configuration, so every later change applies without
waiting. Compare [How changes are
applied]({{< relref "/docs/applying-changes" >}}), where most other settings
wait every time.

## What it costs

Anything set manually in Steam's launch options field is overwritten. The
options that cause this are `env`, `dllOverrides`, `wrappers`, `args`,
`preHook`, `rawLaunchOptions`, `winetricks`, `prefixPath` and `systemd.enable`.
They all need the wrapper, so setting any of them claims the field. Anything
under `files` does not: those are applied during an activation, and an app that
only manages files keeps whatever is in the field.

If you have launch strings you want to keep, move them into `rawLaunchOptions`
rather than leaving them in Steam.

## How the pieces compose

The structured options each fill a different slot in the generated script:

```nix
{
  programs.steam.config.apps."438100" = {
    name = "VRChat";
    env.TZ = null;
    dllOverrides = {
      winhttp = "n,b";
      version = "n,b";
    };
    wrappers = [ "gamemoderun" ];
    args = [ "--fps=60" ];
    preHook = ''
      echo "launching $*"
    '';
  };
}
```

produces roughly:

```bash
unset TZ
export WINEDLLOVERRIDES="version=n,b;winhttp=n,b"

declare -a wrappers=(gamemoderun)
declare -a game_command=("$@")
declare -a args=(--fps=60)

echo "launching $*"

exec env "${wrappers[@]}" "${game_command[@]}" "${args[@]}"
```

The order is fixed: environment first, then wrappers outermost, the game
command, then extra arguments.

`preHook` runs after the `env` exports and the array declarations, and before
`exec`, with `wrappers`, `game_command` and `args` in scope. It can read or
modify them.

## Why dllOverrides exists

Wine takes DLL overrides through the single `WINEDLLOVERRIDES` variable, so
anything setting it directly clobbers every other contributor. `dllOverrides` is
an attribute set that compiles into that one variable, so several sources can
add overrides without fighting. Setting `WINEDLLOVERRIDES` in `env` as well as
`dllOverrides` is rejected for that reason.

## Raw launch options

`rawLaunchOptions` is the classic single-line Steam string, with `%command%`
standing in for the game:

```nix
{
  programs.steam.config.apps."1234560" = {
    name = "Some Game";
    rawLaunchOptions = "DXVK_ASYNC=1 gamemoderun %command% -vulkan";
  };
}
```

It drops into the command position of the same script, wrapped by `wrappers`
with `env` and `args` applied around it. A string with no `%command%` is
appended as arguments, matching Steam's own behaviour. Where both set the same
variable, the raw string wins.

This is for pasting a launch string you already have. For anything you are
writing fresh, the structured options compose more predictably.
