---
title: Install Windows components with Winetricks
weight: 15
---

[Winetricks](https://github.com/Winetricks/winetricks) installs Windows
redistributables and runtimes into a Wine prefix (Visual C++ runtimes, .NET,
fonts, media codecs) which some games and mod loaders need.

```nix
{
  programs.steam.config.apps."1234560" = {
    name = "Some Game";
    winetricks = [ "vcrun2022" "corefonts" ];
  };
}
```

## How and when they are applied

Verbs are installed at launch, not during a rebuild, so:

- The app must use a compatibility tool.
- It must have been launched at least once, so the prefix exists.

They will be re-applied whenever the verb list changes, so the first launch
after a change will be slower, with a desktop notification while they install if
`notifications` is enabled. A failed install will not block the launch, and will
be retried at the next one.

## Reproducibility

Winetricks downloads from upstream at launch, so a verb can change or break when
upstream does.

For DLL-style components you can avoid it. Place the DLLs yourself and declare
the load order instead, see [Use DXVK without
Winetricks]({{< relref "/docs/dxvk" >}}).

Verbs can fail on custom Proton builds that protontricks does not support.
