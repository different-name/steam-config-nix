---
title: Add, replace or hide game files
weight: 33
# the page shipped at this path, so the published link keeps working
aliases:
  - /docs/place-files/
---

Game files are declared by path relative to the game's install directory:

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

Removing an entry from your configuration will revert it: a newly created file
will be deleted, and one that replaced or removed something the game shipped
will be restored from the backup taken before the first write.

The exception is a file that changed since it was written, or a removed file the
game has since put back: it will be left as it is and the backup is dropped.

## Letting the game keep its changes

Each `place` entry has a `mode`:

- `"enforce"` (the default): re-apply the declared contents on every activation.
- `"seed"`: write it once and then leave it alone, which is what you want for
  files the game or you edit in place. Delete the file to push a new version.
- `"lock"`: like `"enforce"`, but the file will be made read-only.

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

To change a few keys in a config the game generates, patch it instead of
replacing it. Keys you do not set will be left untouched:

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

A patch will be re-applied on every activation. Removing it will restore the
original, unless the file has changed since it was last patched. A file cannot
be both placed and patched, and two patches cannot target the same file.

In an `ini` file a key you patch ends up with a single value. Give it a list to
write the key once per element instead, which is how engines such as Unreal
store a multi-valued setting.

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

Prefix files will be skipped until the prefix exists, so launch the game once
before they can be applied.
