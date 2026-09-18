---
title: What managing game files can and cannot undo
weight: 5
---

[Adding, replacing or hiding files]({{< relref "/docs/manage-files" >}}) writes
into the game's install directory or its Proton prefix, and every change is
recorded. Removing an entry from your configuration will revert it on the next
activation: a newly created file will be deleted, and one that replaced or
removed something the game shipped will be restored from the backup taken before
the first write.

A file that changed since it was written will be left alone instead, and its
backup is dropped. That keeps a reversal from throwing away an edit you or the
game made, at the cost of leaving our version in place, so check the log if you
expected a file to come back.

Records live under `$XDG_DATA_HOME/steam-config-nix`. Steam can overwrite
managed files when it updates or verifies a game, and all but `seed` files will
be re-applied on the next activation.

## Saves

Reversing the files does not reverse what the game did while they were there.

A mod that writes to your saves will leave those saves depending on it, and
removing the mod cleanly will not make them whole again.

## Files the game writes

A file placed with the default `"enforce"` mode is written again on every
activation, so a change the game makes to it will be replaced the next time you
rebuild. For a file the game or you should be able to edit, use `mode = "seed"`:
it is written only if the file is absent, and then left alone.

Files you have not declared will never be touched.
