---
title: Set Source engine convars
weight: 23
---

GoldSrc, Source and Source 2 games are configured with console variables, kept
in `.cfg` files under the game's config directory. `autoexec.cfg` is the
conventional place for your own, and it is read at startup.

```nix
{
  programs.steam-config.apps."440" = {
    name = "Team Fortress 2";
    files.game.writeKeys."tf/cfg/autoexec.cfg" = {
      format = "sourceConvars";
      content = {
        fps_max = 0;
        cl_interp_ratio = 1;
      };
      createIfMissing = true;
    };
  };
}
```

`content` is a flat set of console variable to value. Each variable is set in
place if it is already there, or appended if it is not, and binds, aliases and
comments in the file are left untouched.

`createIfMissing = true` is usually right here, because `autoexec.cfg` often
does not exist until you make it.

## Applying and removing

`writeKeys` merges your keys into the game's own file before every launch, and
only the keys you name are touched. A copy of the file as it was before the
first write is kept under
`$XDG_DATA_HOME/steam-config-nix/apps/<app>/originals/`. Removing the entry
leaves your keys in place.
