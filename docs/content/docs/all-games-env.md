---
title: Set environment variables for every game
weight: 37
---

This module configures Steam per app, so it has no global `env`. To set
variables for every Steam game at once, put them in Steam's own environment by
overriding the package:

```nix
{
  programs.steam.package = pkgs.steam.override {
    extraProfile = ''
      export PROTON_ENABLE_WAYLAND=1
      export PRESSURE_VESSEL_FILESYSTEMS_RW="$XDG_RUNTIME_DIR/wivrn/comp_ipc"
      unset TZ
    '';
  };
}
```
