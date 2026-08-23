# Quickstart

```nix
{
  programs.steam.config = {
    enable = true;
    onSteamRunning = "close";
    defaultCompatTool = "GE-Proton";

    apps = {
      "1091500" = {
        name = "Cyberpunk 2077";
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

      "438100" = {
        name = "VRChat";
        env.TZ = null;
      };
    };
  };
}
```

Apps are keyed by their Steam App ID, found in the game's store page URL. From here, each guide covers one feature, or see the [Options Reference](./options.md) for the full list.
