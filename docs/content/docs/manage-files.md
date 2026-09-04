---
title: Add, replace or hide game files
weight: 33
# the page shipped at this path, so the published link keeps working
aliases:
  - /docs/place-files/
---

Dropping a mod into a game, swapping an asset, or hiding a file the game ships
are all the same option, keyed by path relative to the game's install directory:

```nix {eval=false}
{
  programs.steam.config.apps."1234560" = {
    name = "Some Game";
    files.game.place."BepInEx/plugins/plugin.dll".source = ./plugin.dll;
  };
}
```

Everything lives under `files.<location>`, where the location is `game` (the
install directory) or `prefix` (the Proton prefix, `compatdata/<id>/pfx`), and
each location has `place`, `patch` and `remove`.

## Placing and removing files

```nix {eval=false}
{
  programs.steam.config.apps."1966720" = {
    name = "Lethal Company";
    files.game.place = {
      # place a file from a path, keyed by its destination
      "config/settings.ini".source = ./settings.ini;
      # place inline contents instead of a file
      "config/notes.txt".text = "managed by nix";
    };
    # remove a file entirely
    files.game.remove = [ "movies/intro.bik" ];
  };
}
```

Each `place` entry sets exactly one of `source` or `text`. A `source` may be a
file or a directory, and a directory is copied recursively and merged with
whatever is already at the target, so unpacking a mod loader over the game root
leaves the game's own files in place.

Every placed and removed file is tracked, so removing an entry from your
configuration reverts it: a file that was newly created is deleted, and one that
replaced or removed something the game shipped is restored from the backup taken
before the first write.

The exception is a file that changed since we wrote it. If its contents no
longer match what was written, it is left exactly where it is and its backup is
dropped, on the grounds that the newer version is yours or the game's rather
than ours to undo. The same applies to a removed file the game has since put
back.

## Letting the game keep its changes

Each `place` entry has a `mode`:

- `"enforce"` (the default): re-apply the declared contents on every activation.
- `"seed"`: write it once and then leave it alone, which is what you want for
  files the game or you edit in place. Delete the file to push a new version.
- `"lock"`: like `"enforce"`, but the file is made read-only so nothing else can
  change it.

```nix {eval=false}
{
  programs.steam.config.apps."1234560" = {
    name = "Some Game";
    files.game.place."BepInEx/config/MoreCompany.cfg" = {
      source = ./MoreCompany.cfg;
      mode = "seed";
    };
  };
}
```

## Setting keys in a file the game owns

When a game generates its own config and you only want to change a few keys,
patch it instead of replacing the whole file. The patcher reads the file, merges
your keys in, and writes it back, leaving keys you did not mention untouched:

```nix {eval=false}
{
  programs.steam.config.apps."1234560" = {
    name = "Some Game";
    files.game.patch."config/user.ini" = {
      format = "ini";
      content.Video.Fullscreen = 1;
    };
  };
}
```

`createIfMissing` writes a new file with just your keys when the target does not
exist. It is off by default, so a patch against a missing file waits until the
game generates it, retrying on the next activation.

A patch is always re-applied, and the original is backed up and restored when
you remove it. A file cannot be both placed and patched.

## Files in the Proton prefix

Use `files.prefix.place`, `files.prefix.remove` and `files.prefix.patch` to
target the Proton prefix instead, for files under
`drive_c/users/steamuser/AppData` and the like:

```nix {eval=false}
{
  programs.steam.config.apps."1234560" = {
    name = "Some Game";
    files.prefix.place."drive_c/users/steamuser/AppData/LocalLow/Studio/Game/mod.xml".source =
      ./mod.xml;
  };
}
```

The game must be installed, and for prefix files launched once so the prefix
exists, otherwise the file operations are skipped with a warning until it is.
