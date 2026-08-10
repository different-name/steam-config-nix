# Game Files & Mods

Place files into a game's install directory or Proton prefix, patch config files in place, and remove files, for config, asset replacements, mods, or anything else. Every change is tracked and reverted when you remove it from your configuration.

Everything lives under `files.<location>`, where the location is `game` (the install directory) or `prefix` (the Proton prefix, `compatdata/<id>/pfx`), and each location has `place`, `patch` and `remove`.

## Placing and removing files

```nix
{
  programs.steam.config.apps."Lethal Company" = {
    id = 1966720;
    files.game.place = {
      # place a file from a path, keyed by its destination
      "config/settings.ini".source = ./settings.ini;
      # place inline contents instead of a file
      "config/notes.txt".text = "managed by nix";
      # a file the game rewrites: written once, then left alone
      "config/user.cfg" = {
        source = ./user.cfg;
        mode = "seed";
      };
    };
    # remove a file entirely
    files.game.remove = [ "movies/intro.bik" ];
  };
}
```

Each `place` entry sets exactly one of `source` or `text`. A `source` may be a file or a directory, and a directory is copied recursively and merged with whatever is already at the target.

Every placed and removed file is tracked, so removing an entry from your configuration reverts it: replaced and removed files are restored from a backup, and files that were newly created are deleted.

Each `place` entry has a `mode`:

- `"enforce"` (the default): re-apply the declared contents on every activation.
- `"seed"`: write it once and then leave it alone, which is what you want for files the game or you edit in place. Delete the file to push a new version.
- `"lock"`: like `"enforce"`, but the file is made read-only so nothing else can change it.

Use `files.prefix.place` and `files.prefix.remove` to target the Proton prefix instead, for files under `drive_c/users/steamuser/AppData` and the like.

## Patching config files

When a game generates its own config and you only want to change a few keys, patch it instead of replacing the whole file. The patcher reads the file, merges your keys in, and writes it back, leaving keys you did not mention untouched:

```nix
{
  programs.steam.config.apps."Some Game" = {
    id = 1234560;
    files.game.patch."Engine/Config/BaseEngine.ini" = {
      format = "ini";
      content.SystemSettings."r.Tonemapper.Sharpen" = 2;
    };
    files.prefix.patch."drive_c/users/steamuser/AppData/Local/game/settings.json" = {
      format = "json";
      content.graphics.fullscreen = true;
    };
  };
}
```

- `format` is one of `"ini"`, `"json"`, `"registry"`, or `"keyvalue"`. For `ini`, `content` is sections of key to value. For `json` and `keyvalue` (a Valve KeyValues/VDF file), `content` is a nested attribute set deep-merged into the file. For `registry` (a Wine `system.reg`/`user.reg`), `content` maps a backslash-separated key path to value names, where a string becomes a `REG_SZ` and an integer a `REG_DWORD`.
- `whenMissing` defaults to `"create"` (write a new file with just your keys). Set it to `"skip"` to wait until the game generates the file, retrying on the next activation.

A patch is always re-applied, and the original is backed up and restored when you remove it. A file cannot be both placed and patched.

## Installing mods

Mods use the same file management, so a mod setup is reproducible and reverts cleanly when you remove it.

### A mod loader and its plugins

Drop a loader (here BepInEx) and its plugins straight into the install directory, keyed by their path relative to it:

```nix
{
  programs.steam.config.apps."Lethal Company" = {
    id = 1966720;
    files.game.place = {
      # the loader, unpacked into the game root (a directory source is merged in)
      ".".source = pkgs.fetchzip {
        url = "https://github.com/BepInEx/BepInEx/releases/download/v5.4.23.2/BepInEx_win_x64_5.4.23.2.zip";
        hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
        stripRoot = false;
      };
      # a plugin
      "BepInEx/plugins/MoreCompany.dll".source = ./MoreCompany.dll;
    };
  };
}
```

Because a directory `source` is merged into the target, unpacking a loader over the game root leaves the game's own files in place.

### Keeping mod config editable

Many mods write their own config on first run and expect you (or the mod's in-game menu) to edit it. Ship an initial config but let it be edited in place with `mode = "seed"`:

```nix
{
  files.game.place."BepInEx/config/MoreCompany.cfg" = {
    source = ./MoreCompany.cfg;
    mode = "seed"; # written once, then left alone
  };
}
```

### Mods that live in the prefix

For mods or config under the Windows user profile rather than the game directory, target the Proton prefix with `files.prefix.place`:

```nix
{
  files.prefix.place."drive_c/users/steamuser/AppData/LocalLow/Studio/Game/mod.xml" = {
    source = ./mod.xml;
  };
}
```

## Notes

- The game must be installed, and for prefix files launched once (so the prefix exists), otherwise the file operations are skipped with a warning until it is.
- File operations wait for a running game following `onSteamRunning`, so a game running under `skip` defers them to the next activation.
- Steam can overwrite managed files when it updates or verifies a game. They are re-applied on the next activation.
- For runtime components some mods need (for example a specific DLL redistributable), see [Winetricks](./winetricks.md).
