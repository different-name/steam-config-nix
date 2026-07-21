# steam-config-nix

Manage Steam launch options, compat tools and other local config declaratively through your nix config

> [!WARNING]
> This flake is in early development and may be unstable
>
> Please report bugs or request features via the [issues tab](https://github.com/different-name/steam-launch.nix/issues)

> [!IMPORTANT]  
> **Steam must be closed** when writing to the Steam config files
>
> By default changes are applied once Steam exits, Steam will not be touched unless the configuration actually changed
>
> See the `programs.steam.config.onSteamRunning` option to instead close Steam on activation (`"close"`, or `"force-close"` to close even mid-game) or skip until the next activation (`"skip"`)

## Install

Add `steam-config-nix` to your flake inputs

```nix
steam-config-nix = {
  url = "github:different-name/steam-config-nix";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

`steam-config-nix` provides both NixOS and [Home Manager](https://github.com/nix-community/home-manager) modules, so pick one depending on your preference

```nix
# NixOS
imports = [
  inputs.steam-config-nix.nixosModules.default
];
```

```nix
# Home Manager
imports = [
  inputs.steam-config-nix.homeModules.default
];
```

## Usage

See [options.md](options.md) for all available options

#### Quickstart example

```nix
{
  programs.steam.config = {
    enable = true;
    onSteamRunning = "close";
    defaultCompatTool = "GE-Proton";

    apps = {
      "Cyberpunk 2077" = {
        id = 1091500;
        compatTool = "GE-Proton";
        launchOptions = {
          env.WINEDLLOVERRIDES = "winmm,version=n,b";
          args = [
            "--launcher-skip"
            "-skipStartScreen"
          ];
        };
      };

      "VRChat" = {
        id = 438100;
        launchOptions.env.TZ = null;
      };
    };
  };
}
```

### Compatibility Tools

`compatTool` and `defaultCompatTool` accept either the internal name of a compatibility tool that is already installed, or a package containing one:

```nix
{
  programs.steam.config = {
    defaultCompatTool = "proton_experimental";

    apps."Cyberpunk 2077" = {
      id = 1091500;
      compatTool = pkgs.proton-ge-bin;
    };
  };
}
```

Tools provided as packages are installed automatically:

- NixOS: through `programs.steam.extraCompatPackages`, requires `programs.steam.enable`
- Home Manager: linked into `~/.local/share/Steam/compatibilitytools.d`

Versions that are not packaged in nixpkgs can be fetched directly from their releases, any archive containing a `compatibilitytool.vdf` at its root will work:

```nix
{
  compatTool = pkgs.fetchzip {
    url = "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton10-10/GE-Proton10-10.tar.gz";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };
}
```

### Library Artwork

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

### Winetricks

Install [winetricks](https://github.com/Winetricks/winetricks) verbs into an app's Proton prefix:

```nix
{
  programs.steam.config.apps."Some Game" = {
    id = 1234560;
    winetricks = [ "vcrun2022" "corefonts" ];
  };
}
```

Verbs are applied at launch, the prefix and Proton are taken from the environment Steam provides, so the app must use a compatibility tool and have been launched once (so the prefix exists). They are re-applied when the verb list changes, and a failure never blocks the game from launching.

The first launch after adding or changing verbs is slower, as the game waits while the verbs install. A desktop notification (see `notifications`) is shown while this happens.

This is not fully reproducible (winetricks downloads runtimes), but neither is Steam. For DLL-style components (`dxvk`, `vkd3d`) you can instead drop the DLLs and set `launchOptions.env.WINEDLLOVERRIDES` for a pure setup.

Some unusual custom Proton builds are not compatible with protontricks and will fail (harmlessly) to apply verbs.

### Game Files & Mods

Place files into a game's install directory or Proton prefix, for mods, asset replacements, loaders, or config:

```nix
{
  programs.steam.config.apps."Lethal Company" = {
    id = 1966720;
    files.install = {
      # drop a mod, keyed by path relative to the install directory
      "BepInEx/plugins/MoreCompany.dll".source = ./MoreCompany.dll;
      # stub out a file by giving it empty contents
      "movies/intro.bik".text = "";
      # a config the game rewrites: written once, then left alone
      "BepInEx/config/mod.cfg" = {
        source = ./mod.cfg;
        overwriteChanges = false;
      };
    };
    # remove a file entirely
    removeFiles.install = [ "unwanted.dll" ];
  };
}
```

Files are copied in. A `source` may be a file or a directory, which is copied recursively and merged with whatever is already there. Every placed and removed file is tracked, so removing an entry from your configuration reverts it: replaced and removed files are restored from a backup, and files that were newly created are deleted.

By default a file is re-applied on every activation. Set `overwriteChanges = false` to write it once and then leave it alone, which is what you want for configs the game or you edit in place. Delete the file to push a new version.

Use `files.prefix` and `removeFiles.prefix` to target the Proton prefix (`compatdata/<id>/pfx`) instead, for files under `drive_c/users/steamuser/AppData` and the like. The prefix only exists once the game has been launched.

- The game must be installed (and, for the prefix, launched once), otherwise the file operations are skipped with a warning until it is.
- File operations wait for a running game following `onSteamRunning`, so a game running under `skip` defers them to the next activation.
- Steam can overwrite replaced files when it updates or verifies a game. They are re-applied on the next activation.

### Desktop Entries

Any app can generate a desktop entry that launches it through Steam, so your application launcher can start it directly:

```nix
{
  programs.steam.config.apps."Cyberpunk 2077" = {
    id = 1091500;
    # name, comment, icon and categories all have sensible defaults
    desktopEntry.enable = true;
  };
}
```

This works for non-Steam apps too, where the name and icon default to the app's own `name` and `icon`.

### Global Configuration

It is not possible to perform any global configuration of games through Steam configuration

To set environment variables for all Steam games, override `extraProfile` in the Steam package:

```nix
{
  programs.steam.package = pkgs.steam.override {
    extraProfile = ''
      export PROTON_ENABLE_WAYLAND=1
      export PRESSURE_VESSEL_FILESYSTEMS_RW="$XDG_RUNTIME_DIR/wivrn/comp_ipc"
      unset TZ
    '';
  };
}
```

## Acknowledgements

- https://github.com/FeralInteractive/gamemode/issues/177 for the idea
