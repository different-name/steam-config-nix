---
title: What managing game files changes on disk
weight: 5
---

[Adding, replacing or hiding files]({{< relref "/docs/manage-files" >}}) with
`overlay` and `hide` changes no files in the game's install directory or its
Proton prefix. A missing directory an entry needs is created empty. The entries
are laid over the real directory for one launch, in the game's own mount
namespace, and are gone when the game exits. Steam's verification sees the game
exactly as it shipped.

`writeDefault` and `writeKeys` write to disk:

- `writeDefault` writes a file when it is missing, and leaves it alone while it
  exists.
- `writeKeys` rewrites the keys you name in a file the game owns, before every
  launch. The file as it was before the first write is kept under
  `$XDG_DATA_HOME/steam-config-nix/apps/<app>/originals/`.

Removing either entry leaves the file as it is. A target inside a directory the
overlay covers is written to the `writes` directory below, not to disk. Files
you have not declared are never touched.

## The game's own writes

While an overlay covers a directory, what the game writes there goes to
`$XDG_DATA_HOME/steam-config-nix/apps/<app>/writes/` rather than to disk, and
the game sees it again at the next launch. Three kinds of write do not survive,
and each is logged by the launch step:

- a change the game makes to a served file or a hidden path is discarded at the
  start of every launch
- when you change or remove an entry, the copies of the files it used to serve
  are dropped
- a copy of a real file is dropped when Steam updates that file underneath it

Directories listed in `passthrough` are written in place.

## Saves

A save written while a mod was served depends on that mod. Removing the entry
does not make the save whole again.
