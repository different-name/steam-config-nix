# Quickstart

```nix
{
  programs.steam.config = {
    enable = true;
    onSteamRunning = "close";
    defaultCompatTool = "GE-Proton";

    apps = {
      "Cyberpunk 2077" = {
        id = 1091500;
        compatTool = "GE-Proton";
        dllOverrides = {
          winmm = "n,b";
          version = "n,b";
        };
        args = [
          "--launcher-skip"
          "-skipStartScreen"
        ];
      };

      "VRChat" = {
        id = 438100;
        env.TZ = null;
      };
    };
  };
}
```

Apps are keyed by any name you like. The `id` is the Steam App ID, found in the game's store page URL. From here, each guide covers one feature, or see the [Options Reference](./options.md) for the full list.
