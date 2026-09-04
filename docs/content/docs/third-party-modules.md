---
title: Third party modules
weight: 51
---

steam-config-nix manages Steam's configuration and your game files. Per-game
behaviour and fixes live in separate modules that build on top of it.

## Modules

- [vrchat-video-resolver](https://github.com/different-name/vrchat-video-resolver):
  repairs VRChat's in-world video playback on Linux. See
  [VRChat]({{< relref "/docs/vrchat" >}}).

If you maintain a module that builds on steam-config-nix, open a pull request to
add it here.

## Writing one

A module that builds on steam-config-nix is an ordinary NixOS or Home Manager
module that sets options under `programs.steam.config`, most often `env`,
`wrappers`, `files` or `systemd.enable` for a specific app.

Because everything composes through the module system, several such modules can
configure the same app without conflicting. `env` and `dllOverrides` in
particular merge rather than clobber, which is [why dllOverrides
exists]({{< relref "/docs/launch-options#why-dlloverrides-exists" >}}).

Use `lib.mkDefault` for anything a user might reasonably want to override.

## Setting files changes the installed game

An app with anything under `files` has those entries written into its install
directory or its Proton prefix on activation. Your users get that whether or not
they know your module sets it, so say so in your readme, and think about whether
the app has anti-cheat before shipping a `files` entry for it. See
[Add, replace or hide game files]({{< relref "/docs/manage-files" >}}).

