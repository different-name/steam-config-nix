---
title: How launch options work
weight: 4
---

Steam gives each app a single launch options string. The module compiles your
configuration into a wrapper script at a stable path outside Steam, and puts
only a command that runs it into Steam:

```
/bin/sh -c 'if [ -x "$0" ]; then exec "$0" "$@"; else exec "$@"; fi' <wrapper> %command%
```

## When changes apply

Steam's launch options field is written once, when the app first needs the
wrapper. That write lands in Steam's own configuration, so it waits for Steam to
close like anything else there. After it, a change to your configuration only
rewrites the script, so it will apply without waiting.

## Launch options set in Steam

Most options make use of the wrapper script, so in most cases whatever was set
manually in Steam's launch options field will be overwritten.

If you have launch strings you want to keep, move them into `rawLaunchOptions`
rather than leaving them in Steam.

## The generated script

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

## DLL overrides

Wine reads DLL overrides from the single `WINEDLLOVERRIDES` variable.
`dllOverrides` compiles into it, so several modules can each add overrides.
Setting `WINEDLLOVERRIDES` in `env` as well as `dllOverrides` will be rejected.

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

Use it to paste a launch string you already have, and the structured options for
anything new.
