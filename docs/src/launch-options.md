# Launch Options

> [!NOTE]
> These options overwrite any launch options set manually in Steam: `env`, `dllOverrides`, `wrappers`, `args`, `preHook`, `rawLaunchOptions`, [`winetricks`](./winetricks.md) and [`systemd.enable`](./systemd-integration.md).
>
> This is because they use a wrapper script, which is applied using Steam's launch options.

An app's launch is assembled from structured pieces set directly on the app: `env`, `dllOverrides`, `wrappers`, `args` and `preHook`. There is also `rawLaunchOptions` for pasting a classic Steam launch string, which composes with the structured pieces rather than replacing them.

## Structured launch options

```nix
{
  programs.steam.config.apps."Cyberpunk 2077" = {
    id = 1091500;
    env.TZ = null; # unset a variable by giving it null
    dllOverrides = {
      winmm = "n,b";
      version = "n,b";
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
}
```

- `env`: environment variables to export before launch. A value of `null` unsets the variable instead of setting it.
- `dllOverrides`: DLL load orders, an attribute set mapping a DLL name to a mode (`"n"` native, `"b"` builtin, `"n,b"`, `"b,n"`, or `"disabled"`). These compile into the single `WINEDLLOVERRIDES` variable, so mods and other sources can each contribute overrides without clobbering one another. Setting `WINEDLLOVERRIDES` directly in `env` instead is an error.
- `wrappers`: executables to wrap the game with, given as a name on `PATH` or a package (a package is resolved with `lib.getExe`).
- `args`: extra arguments appended to the game command.
- `preHook`: bash to run just before launch. The `wrappers`, `game_command` and `args` bash arrays are in scope for you to read or modify.

This compiles to a small wrapper script. The example above produces roughly:

```bash
unset TZ
export WINEDLLOVERRIDES="version=n,b;winmm=n,b"

declare -a wrappers=(gamemoderun /nix/store/...-mangohud/bin/mangohud)
declare -a game_command=("$@")
declare -a args=(--launcher-skip)

echo "launching $*"

exec env "${wrappers[@]}" "${game_command[@]}" "${args[@]}"
```

## Gamescope

gamescope is just another wrapper: list it first, with its own flags terminated by `--`, and the game runs inside its nested compositor.

```nix
{
  programs.steam.config.apps."Elden Ring" = {
    id = 1245620;
    wrappers = [
      (lib.getExe pkgs.gamescope)
      "-W" "2560" # output width
      "-H" "1440" # output height
      "-r" "144" # refresh rate
      "-f" # fullscreen
      "--"
    ];
  };
}
```

The `--` ends gamescope's own options, so everything after it, the game command and any further wrappers, runs inside the session. To combine it with another wrapper keep gamescope outermost: `[ (lib.getExe pkgs.gamescope) "--" "gamemoderun" ]` runs gamemode inside gamescope.

## Raw launch options

`rawLaunchOptions` is the classic single-line Steam launch string, where `%command%` stands in for the game's own command:

```nix
{
  programs.steam.config.apps."Some Game" = {
    id = 1234560;
    rawLaunchOptions = "DXVK_ASYNC=1 gamemoderun %command% -vulkan";
  };
}
```

Use it to paste an existing launch string verbatim. It composes with the structured options: the raw string drops into the command position, wrapped by `wrappers` with `env` and `args` applied around it. A string with no `%command%` is appended to the game command as arguments, as in Steam. On a variable set by both, the raw string wins.

## How they are applied

Both compile to a wrapper script at a stable path in your home directory, and Steam's launch options field only holds `<wrapper> %command%`. That path is written to Steam once. After that, changing your launch options rewrites the script rather than Steam's config, so updates apply without waiting for Steam to close.
