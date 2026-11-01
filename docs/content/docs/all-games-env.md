---
title: Set environment variables for every game
weight: 37
---

`programs.steam-config.env` sets variables for every game and non-Steam app
Steam launches, whether or not it has an entry in `apps`:

```nix
{
  programs.steam-config.env = {
    PROTON_ENABLE_WAYLAND = 1;
    TZ = null;
  };
}
```

`null` unsets a variable. An app's own `env` takes precedence for the variables
it sets.

These reach what Steam launches, not Steam itself. For a variable Steam's own
process has to see, put it in Steam's environment by overriding the package the
launcher starts:

```nix
{
  programs.steam-config.steamPackage = pkgs.steam.override {
    extraProfile = ''
      export PRESSURE_VESSEL_FILESYSTEMS_RW="$XDG_RUNTIME_DIR/wivrn/comp_ipc"
    '';
  };
}
```
