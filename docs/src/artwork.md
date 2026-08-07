# Library Artwork

Apps can have custom Steam library artwork, sourced from local files or fetched (e.g. from [SteamGridDB](https://steamgriddb.com)):

```nix
{
  programs.steam.config.nonSteamApps."Super Tux Kart" = {
    target = lib.getExe pkgs.supertuxkart;

    artwork = {
      icon = ./icon.png; # non-Steam apps only
      cover = pkgs.fetchurl {
        url = "https://cdn2.steamgriddb.com/grid/...";
        hash = "...";
      };
      header = ./header.jpg;
      hero = ./hero.jpg;
      logo = ./logo.png;
    };
  };
}
```

`cover`, `header`, `hero` and `logo` work for both Steam and non-Steam apps. `icon` is non-Steam only, as Steam manages the icons of its own apps.
