---
title: Patch an Unreal Engine game
weight: 21
---

Unreal Engine games keep their settings in `.ini` files, usually under
`Engine/Config/` in the install directory or under the Windows user profile in
the prefix. Many of the tweaks people share for UE games (disabling motion blur,
unlocking framerates, changing scalability) are edits to those files.

Patch them rather than replacing them, so the keys you did not mention survive a
game update:

```nix
{
  programs.steam.config.apps."1234560" = {
    name = "Some Game";
    files.game.patch."Engine/Config/BaseEngine.ini" = {
      format = "ini";
      content.SystemSettings."r.Tonemapper.Sharpen" = 2;
    };
  };
}
```

`content` is sections of key to value, matching the file's own shape. Each key
you name is set in place, and the rest of the file, including comments, ordering
and settings you did not mention, is left as it was. Unreal writes some list
valued settings as a repeated key, and patching one of those collapses it to a
single line holding your value.

## Files in the prefix

Per-user settings live in the prefix rather than the install directory:

```nix
{
  programs.steam.config.apps."1234560" = {
    name = "Some Game";
    files.prefix.patch."drive_c/users/steamuser/Documents/My Games/SomeGame/Saved/Config/WindowsNoEditor/Engine.ini" = {
      format = "ini";
      content.SystemSettings."r.MotionBlurQuality" = 0;
    };
  };
}
```

The exact path varies by game and engine version. Launch the game once, then go
looking, the prefix does not exist until then, and a patch against a file that
is not there yet waits rather than failing.

## Related

The `createIfMissing` option gives the game a file containing just your keys
when the target does not exist. It is off by default, which is usually right for
engine configs, you want the game to generate its own first.

## How the keys reach the game

`patch` merges your keys into the game's own file on activation. Only the keys
you name are touched, and the original is backed up before the first write, so
removing the entry restores it.
