# Launch Options

There are two ways to set an app's launch options, `launchOptions` and `launchOptionsStr`. These options are exclusive and only one can be used.

## Nix-style launch options

`launchOptions` builds the launch command from structured pieces, so you do not have to hand-write a `%command%` string:

```nix
{
  programs.steam.config.apps."Cyberpunk 2077" = {
    id = 1091500;
    launchOptions = {
      env = {
        WINEDLLOVERRIDES = "winmm,version=n,b";
        TZ = null; # unset a variable by giving it null
      };
      wrappers = [
        "gamemoderun"
        (lib.getExe pkgs.mangohud)
      ];
      args = [ "--launcher-skip" ];
      preHook = ''
        echo "launching $*"
      '';
    };
  };
}
```

- `env`: environment variables to export before launch. A value of `null` unsets the variable instead of setting it.
- `wrappers`: executables to wrap the game with, given as a name on `PATH` or a package (a package is resolved with `lib.getExe`).
- `args`: extra arguments appended to the game command.
- `preHook`: bash to run just before launch. The `wrappers`, `game_command` and `args` bash arrays are in scope for you to read or modify.

This compiles to a small wrapper script. The example above produces roughly:

```bash
export WINEDLLOVERRIDES="winmm,version=n,b"
unset TZ

declare -a wrappers=(gamemoderun /nix/store/…-mangohud/bin/mangohud)
declare -a game_command=("$@")
declare -a args=(--launcher-skip)

echo "launching $*"

exec env "${wrappers[@]}" "${game_command[@]}" "${args[@]}"
```

## Traditional launch options

`launchOptionsStr` is the classic single-line Steam launch string, where `%command%` stands in for the game's own command:

```nix
{
  programs.steam.config.apps."Some Game" = {
    id = 1234560;
    launchOptionsStr = "MANGOHUD=1 gamemoderun %command% -vulkan";
  };
}
```

Use this when you are copying an existing launch string or want full control of the line. For anything you would assemble yourself, `launchOptions` is usually clearer.

## How they are applied

Both styles compile to a wrapper script at a stable path in your home directory, and Steam's launch options field only holds `<wrapper> %command%`. That path is written to Steam once. After that, changing your launch options rewrites the script rather than Steam's config, so updates apply without waiting for Steam to close. It is also why a traditional `launchOptionsStr` is written to a file, instead of straight into Steam.
