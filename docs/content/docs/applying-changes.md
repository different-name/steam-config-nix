---
title: How changes are applied
weight: 3
---

Steam holds its configuration files open while it runs and rewrites them from
memory when it exits, so anything written while Steam is running is discarded
the moment you close it.

## What has to wait for Steam to close

Settings that live in Steam's own files (compatibility tools, shortcuts for
non-Steam apps, betas, languages and the other per-app settings, library folders
and the client settings) are written by a user service that runs at activation.
When Steam is running and something has to change, it waits by default.

Launch options never reach those files. Each app's `env`, `args`, `wrappers`,
`files` and the rest go into a launch spec the launch step reads at the next
game launch. See [How launch options
work]({{< relref "/docs/launch-options" >}}).

## Choosing what happens

`onSteamRunning` decides what the service does when it needs to write and Steam
is in the way:

- `"wait"` (default): wait for Steam to exit, then apply
- `"close"`: close Steam and apply, waiting for any running game to exit first
- `"force-close"`: close Steam and apply immediately, even mid-game
- `"skip"`: skip writing, the changes apply on the next activation

## Game files are applied at launch

Everything under `files` is applied by the launch step, every time the app
starts. A rebuild does not touch a game's directory, so `onSteamRunning` does
not govern it, and a game that is not launched through Steam gets none of it.

## What waits for the game

- A game that has never been launched has no Proton prefix, so its
  `files.prefix` entries and winetricks verbs wait until it has been launched
  once.
- A `writeKeys` entry waits for the game to generate its target file, unless you
  set `createIfMissing`.
