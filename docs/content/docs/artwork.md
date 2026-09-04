---
title: Use custom library artwork
weight: 17
---

Steam shows several images per app, and for non-Steam shortcuts it shows none
until you supply them. [SteamGridDB](https://steamgriddb.com) is where most
people get replacements.

```nix
{
  programs.steam.config.nonSteamApps."Super Tux Kart" = {
    target = lib.getExe pkgs.supertuxkart;

    artwork = {
      icon = ./icon.png;     # non-Steam apps only
      cover = pkgs.fetchurl {
        url = "https://cdn2.steamgriddb.com/grid/....png";
        hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
      header = ./header.jpg;
      hero = ./hero.jpg;
      logo = ./logo.png;
    };
  };
}
```

Any of them may be a local path or a fetched file. Fetching keeps the images out
of your repository at the cost of pinning a hash.

## Which image is which

- `cover`: the vertical box art in the library grid
- `header`: the horizontal capsule
- `hero`: the wide banner behind the app page
- `logo`: the transparent title overlaid on the hero

`cover`, `header`, `hero` and `logo` work for both Steam and non-Steam apps.
`icon` is non-Steam only, because Steam manages the icons of its own apps.
