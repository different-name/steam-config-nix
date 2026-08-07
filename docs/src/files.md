# Game Files & Mods

Place files into a game's install directory or Proton prefix, and remove files from them, for config, asset replacements, mods, or anything else. Every change is tracked and reverted when you remove it from your configuration.

## Placing and removing files

```nix
{
  programs.steam.config.apps."Lethal Company" = {
    id = 1966720;
    files.install = {
      # place a file from a path, keyed by its destination
      "config/settings.ini".source = ./settings.ini;
      # place inline contents instead of a file
      "config/notes.txt".text = "managed by nix";
      # a file the game rewrites: written once, then left alone
      "config/user.cfg" = {
        source = ./user.cfg;
        overwriteChanges = false;
      };
    };
    # remove a file entirely
    removeFiles.install = [ "movies/intro.bik" ];
  };
}
```

Each entry sets exactly one of `source` or `text`. A `source` may be a file or a directory, and a directory is copied recursively and merged with whatever is already at the target.

Every placed and removed file is tracked, so removing an entry from your configuration reverts it: replaced and removed files are restored from a backup, and files that were newly created are deleted.

By default a file is re-applied on every activation. Set `overwriteChanges = false` to write it once and then leave it alone, which is what you want for files the game or you edit in place. Delete the file to push a new version.

Use `files.prefix` and `removeFiles.prefix` to target the Proton prefix (`compatdata/<id>/pfx`) instead, for files under `drive_c/users/steamuser/AppData` and the like.

## Installing mods

Mods use the same file management, so a mod setup is reproducible and reverts cleanly when you remove it.

### A mod loader and its plugins

Drop a loader (here BepInEx) and its plugins straight into the install directory, keyed by their path relative to it:

```nix
{
  programs.steam.config.apps."Lethal Company" = {
    id = 1966720;
    files.install = {
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

Many mods write their own config on first run and expect you (or the mod's in-game menu) to edit it. Ship an initial config but let it be edited in place with `overwriteChanges = false`:

```nix
{
  files.install."BepInEx/config/MoreCompany.cfg" = {
    source = ./MoreCompany.cfg;
    overwriteChanges = false; # written once, then left alone
  };
}
```

### Mods that live in the prefix

For mods or config under the Windows user profile rather than the game directory, target the Proton prefix with `files.prefix`:

```nix
{
  files.prefix."drive_c/users/steamuser/AppData/LocalLow/Studio/Game/mod.xml" = {
    source = ./mod.xml;
  };
}
```

## Notes

- The game must be installed, and for prefix files launched once (so the prefix exists), otherwise the file operations are skipped with a warning until it is.
- File operations wait for a running game following `onSteamRunning`, so a game running under `skip` defers them to the next activation.
- Steam can overwrite managed files when it updates or verifies a game. They are re-applied on the next activation.
- For runtime components some mods need (for example a specific DLL redistributable), see [Winetricks](./winetricks.md).
