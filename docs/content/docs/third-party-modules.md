---
title: Third party modules
weight: 51
---

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

Several modules can configure the same app. `env`, `dllOverrides` and `files`
merge by key, lists such as `wrappers` are concatenated and `preHook` is joined,
but a single value such as one `env` variable, given two different values, will
fail to evaluate.

Use `lib.mkDefault` for anything a user might reasonably want to override.

## Setting files changes the installed game

An app with anything under `files` has those entries written into its install
directory or its Proton prefix on activation. Your users get that whether or not
they know your module sets it, so say so in your readme, and think about whether
the app has anti-cheat before shipping a `files` entry for it. See [Add, replace
or hide game files]({{< relref "/docs/manage-files" >}}).
