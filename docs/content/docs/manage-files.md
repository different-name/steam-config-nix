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
  programs.steam-config.apps."1234560" = {
    name = "Some Game";
    files.game.overlay."BepInEx/plugins/plugin.dll".source = ./plugin.dll;
  };
}
```

Everything lives under `files.<location>`, where the location is `game` (the
install directory, Steam apps only) or `prefix` (the Proton prefix,
`compatdata/<id>/pfx`). Each location has `overlay`, `hide` and `passthrough`,
which change what the game sees for one session, and `writeDefault` and
`writeKeys`, which write to disk.

All of it is applied by the launch step, every time the app starts through
Steam. A rebuild does not touch the game's directory.

## Serving and hiding files

```nix {eval=false}
{
  programs.steam-config.apps."1966720" = {
    name = "Lethal Company";
    files.game.overlay = {
      # a file from a path, keyed by where the game sees it
      "config/settings.ini".source = ./settings.ini;
      # inline contents instead of a file
      "config/notes.txt".text = "managed by nix";
    };
    # the game does not see this one
    files.game.hide = [ "movies/intro.bik" ];
  };
}
```

Each `overlay` entry sets exactly one of `source` or `text`. The entry is laid
over the real directory for the session: the game sees it at that path, and the
files on disk are not changed. A `source` may be a directory, which merges with
whatever is already there, so unpacking a mod loader over the game root leaves
the game's own files in view.

`hide` makes a path invisible to the game. The real file stays.

Removing an entry from your configuration is enough to undo it.

Set `readOnly = true` on an entry the game overwrites at startup.

## Where the game's writes go

The overlay covers the directory holding each declared path. An entry at the
root of the install directory covers all of it. Anything the game writes inside
a covered directory lands under
`$XDG_DATA_HOME/steam-config-nix/apps/<app>/writes/<location>` instead of on
disk, where `<app>` is the app ID, or for a non-Steam app its attribute name
lowercased with `-` for anything outside `a-z0-9`. The game sees its writes
again at the next launch, except for changes to the served and hidden paths
themselves, which are discarded. See [What managing game files changes on
disk]({{< relref "/docs/game-files" >}}).

For a directory the game should write in place, such as saves that Steam Cloud
syncs, list it in `passthrough`:

```nix {eval=false}
{
  programs.steam-config.apps."1234560" = {
    name = "Some Game";
    files.game.overlay."winhttp.dll".source = ./winhttp.dll;
    files.game.passthrough = [ "Saves" ];
  };
}
```

A served or hidden path cannot be inside a passthrough directory.

## Letting the game keep its changes

`writeDefault` writes a file once, before the first launch where it is missing,
and then leaves it alone. The game and you own it from then on, and a changed
`source` is not written until the file is deleted:

```nix {eval=false}
{
  programs.steam-config.apps."1234560" = {
    name = "Some Game";
    files.game.writeDefault."BepInEx/config/MoreCompany.cfg".source = ./MoreCompany.cfg;
  };
}
```

## Setting keys in a file the game owns

To change a few keys in a config the game generates, set them in place instead
of replacing the file. Keys you do not name are kept:

```nix {eval=false}
{
  programs.steam-config.apps."1234560" = {
    name = "Some Game";
    files.game.writeKeys."config/user.ini" = {
      format = "ini";
      content.Video.Fullscreen = 1;
    };
  };
}
```

`createIfMissing` writes a new file with just your keys when the target does not
exist. Without it, an entry for a missing file is skipped until the game
generates it, checked again at the next launch.

The keys are written before every launch. A `writeDefault` or `writeKeys` target
inside a directory the overlay covers goes to the `writes` directory instead,
like any other write made there. A copy of the file as it was before the first
write is kept under
`$XDG_DATA_HOME/steam-config-nix/apps/<app>/originals/<location>`. Removing the
entry leaves your keys in place. A path can only be in one of `overlay`, `hide`,
`writeDefault` and `writeKeys`.

In an `ini` file a key you set ends up with a single value. Give it a list to
write the key once per element instead, which is how engines such as Unreal
store a multi-valued setting.

## Files in the Proton prefix

Use `files.prefix` to target the Proton prefix instead, for files under
`drive_c/users/steamuser/AppData` and the like:

```nix {eval=false}
{
  programs.steam-config.apps."1234560" = {
    name = "Some Game";
    files.prefix.overlay."drive_c/users/steamuser/AppData/LocalLow/Studio/Game/mod.xml".source =
      ./mod.xml;
  };
}
```

Prefix files are skipped until the prefix exists, so launch the game once before
they can be applied.

## Requirements

The overlay is mounted with bubblewrap in the game's own mount namespace, which
needs unprivileged user namespaces. When the mounts cannot be set up, or another
launch of the same app is still using them, the game starts without its files
and a notification says so.
