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

## Game files wait for the game, not for Steam

Everything under `files` is written into the game's install directory or its
Proton prefix during an activation. Steam does not own those files, so
`onSteamRunning` does not govern them: they are applied whether or not Steam is
running. A running game does hold them up, because replacing a file underneath a
game that has it open is how you get a crash, so the activation waits for that
game to exit first.

Removing an entry reverts it on the next activation. What that does and does not
put back is covered in [what managing game files can and cannot
undo]({{< relref "/docs/game-files" >}}).

## When nothing happens at all

Some work is deferred rather than blocked:

- A game that has never been launched has no Proton prefix, so its prefix files
  are left for the next launch, and winetricks verbs wait for the launch after
  the prefix exists.
- A patch waits for the game to generate its target file, unless you set
  `createIfMissing`.

Each location is handled separately, so a game whose install directory is
reachable but whose prefix is not gets only the first applied, and says which
one it could not do.
