# Winetricks

Install [winetricks](https://github.com/Winetricks/winetricks) verbs into an app's Proton prefix:

```nix
{
  programs.steam.config.apps."Some Game" = {
    id = 1234560;
    winetricks = [ "vcrun2022" "corefonts" ];
  };
}
```

Verbs are applied at launch. The prefix and Proton come from the environment Steam provides, so the app must use a compatibility tool and have been launched once (so the prefix exists). They are re-applied when the verb list changes, and a failure never blocks the game from launching.

The first launch after adding or changing verbs is slower, as the game waits while the verbs install. A desktop notification (see [Configuration](./configuration.md)) is shown while this happens.

This is not fully reproducible (winetricks downloads runtimes), but neither is Steam. For DLL-style components (`dxvk`, `vkd3d`) you can instead drop the DLLs and set `launchOptions.env.WINEDLLOVERRIDES` for a pure setup.

Some unusual custom Proton builds are not compatible with protontricks and will fail (harmlessly) to apply verbs.
