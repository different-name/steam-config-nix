---
title: How changes are applied
weight: 3
---

Steam holds its configuration files open while it runs and rewrites them from
memory when it exits, so anything written while Steam is running is discarded
the moment you close it.

## What has to wait for Steam to close

Settings that live in Steam's own files (compatibility tool mappings, shortcuts
for non-Steam apps, launch options, per-app manifest settings) can only be
written while Steam is not running. So the module writes them when Steam is
closed, and by default waits for that to happen.

Most of what the module does never reaches those files. Options that need the
wrapper compile into a script, and the launch options field holds nothing but a
pointer to it, so only the first of those changes waits. See [How launch options
work]({{< relref "/docs/launch-options" >}}).

## Choosing what happens

`onSteamRunning` decides what an activation does when it needs to write and
Steam is in the way:

- `"wait"` (default): wait for Steam to exit, then apply
- `"close"`: close Steam and apply, waiting for any running game to exit first
- `"force-close"`: close Steam and apply immediately, even mid-game
- `"skip"`: skip writing, the changes apply on the next activation

## Game files are applied every activation

Everything under `files` is applied to the game's install directory or its
Proton prefix on every activation. Steam does not own those files, so
`onSteamRunning` does not govern them.

Removing an entry will revert it on the next activation. If any game is running,
the activation will wait for it to exit first. See [what managing game files can
and cannot undo]({{< relref "/docs/game-files" >}}).

## What waits for the game

- A game that has never been launched has no Proton prefix, so its prefix files
  and winetricks verbs wait until it has been launched once.
- A patch will wait for the game to generate its target file, unless you set
  `createIfMissing`.
