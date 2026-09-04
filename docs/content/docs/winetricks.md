---
title: Install Windows components with Winetricks
weight: 15
---

[Winetricks](https://github.com/Winetricks/winetricks) installs Windows
redistributables and runtimes into a Wine prefix (Visual C++ runtimes, .NET,
fonts, media codecs) which some games and most mod loaders need.

```nix
{
  programs.steam.config.apps."1234560" = {
    name = "Some Game";
    winetricks = [ "vcrun2022" "corefonts" ];
  };
}
```

## How and when they are applied

Verbs are installed at launch, not during a rebuild, because the prefix and the
Proton build come from the environment Steam provides. So:

- The app must use a compatibility tool.
- It must have been launched at least once, so the prefix exists.
- A prefix moved with `prefixPath` is followed.

They are re-applied whenever the verb list changes. The first launch after a
change is slower, since the game waits while the verbs install, and if
`notifications` is enabled, a desktop notification will let you know. A failure
never blocks the game from launching.

## What this costs you

Winetricks downloads runtimes from the internet at launch, so this is the least
reproducible thing the module does.

For DLL-style components you can avoid it. Place the DLLs yourself and declare
the load order instead, see [Use DXVK without
Winetricks]({{< relref "/docs/dxvk" >}}).

Some unusual custom Proton builds are not compatible with protontricks and will
fail, harmlessly, to apply verbs.
