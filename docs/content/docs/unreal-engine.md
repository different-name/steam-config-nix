---
title: Patch an Unreal Engine game
weight: 21
---

Unreal Engine games keep their settings in `.ini` files, usually under
`Engine/Config/` in the install directory or under the Windows user profile in
the prefix.

Set keys in them to change only the ones you name:

```nix
{
  programs.steam-config.apps."1234560" = {
    name = "Some Game";
    files.game.writeKeys."Engine/Config/BaseEngine.ini" = {
      format = "ini";
      content.SystemSettings."r.Tonemapper.Sharpen" = 2;
    };
  };
}
```

`content` is sections of key to value, matching the file's own shape. Each key
you name is set in place, and the rest of the file is left as it was. Unreal
writes some list valued settings as a repeated key: give a list to write one
line per element, since a single value will collapse them to one line.

## Files in the prefix

Per-user settings live in the prefix rather than the install directory:

```nix
{
  programs.steam-config.apps."1234560" = {
    name = "Some Game";
    files.prefix.writeKeys."drive_c/users/steamuser/Documents/My Games/SomeGame/Saved/Config/WindowsNoEditor/Engine.ini" = {
      format = "ini";
      content.SystemSettings."r.MotionBlurQuality" = 0;
    };
  };
}
```

The exact path varies by game and engine version, so launch the game once and
look. An entry for a file that is not there yet is skipped until the game
creates it.

## Creating the file

`createIfMissing = true` will create the file with just your keys when it is
missing. Leave it off for engine configs, so the game generates its own.

## Applying and removing

`writeKeys` merges your keys into the game's own file before every launch, and
only the keys you name are touched. A copy of the file as it was before the
first write is kept under
`$XDG_DATA_HOME/steam-config-nix/apps/<app>/originals/`. Removing the entry
leaves your keys in place.
