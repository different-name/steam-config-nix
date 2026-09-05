---
title: What managing game files can and cannot undo
weight: 5
---

[Adding, replacing or hiding files]({{< relref "/docs/manage-files" >}}) writes
into the game's install directory or its Proton prefix, and every change is
recorded. Removing an entry from your configuration reverts it on the next
activation: a file that was newly created is deleted, and one that replaced or
removed something the game shipped is restored from the backup taken before the
first write.

A file that changed since we wrote it is left alone instead, and its backup is
dropped. That keeps a reversal from throwing away an edit you or the game made,
at the cost of leaving our version in place, so check the log if you expected a
file to come back.

The records themselves live under `$XDG_DATA_HOME/steam-config-nix`. Steam can
overwrite managed files when it updates or verifies a game, and they are
re-applied on the next activation.

## What it does not undo

Reversing the files does not reverse what the game did while they were there.

A mod that writes to your saves leaves those saves depending on it. Bethesda
games record which plugins a save was made with, Minecraft worlds reference
block IDs that a mod introduced, and Factorio refuses to load a save whose mods
are gone. Removing the mod cleanly does not make those saves whole again.

## What the game writes

A file placed with the default `"enforce"` mode is written again on every
activation, so a change the game makes to it is replaced the next time you
rebuild. For a file the game or you should be able to edit, use `mode = "seed"`:
it is written once and then left alone.

Anything the game writes that you have not declared is its own, and is never
touched.
