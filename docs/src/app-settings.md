# Steam App Settings

Some per-app Steam settings can be managed declaratively. These are written into the app's manifest, so the app must be installed for them to apply, and Steam picks them up on its next start. When you unset an option, the app reverts to Steam's default.

```nix
{
  programs.steam.config.apps."Cyberpunk 2077" = {
    id = 1091500;
    betaBranch = "prerelease";
    language = "german";
    updateBehavior = "onLaunch";
    allowDownloadsWhileRunning = "always";
  };
}
```

- `betaBranch`: opt the app into a beta branch. Steam downloads the branch's build on its next start.
- `language`: the app language, given as a Steam API language name such as `"english"`, `"german"` or `"schinese"`.
- `updateBehavior`: how Steam keeps the app updated:
  - `"always"`: always keep it updated
  - `"onLaunch"`: only update when launched
  - `"highPriority"`: update this app before others
- `allowDownloadsWhileRunning`: whether Steam may download other apps while this one runs:
  - `"followGlobal"`: use the global download setting
  - `"always"`: always allow downloads while it runs
  - `"never"`: never allow downloads while it runs

These settings apply to Steam apps only, not [non-Steam apps](./non-steam-apps.md).
