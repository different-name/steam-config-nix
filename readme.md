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
      cyberpunk-2077 = {
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

      vrchat = {
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

    apps.cyberpunk-2077 = {
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

### Desktop Entries

Any app can generate a desktop entry that launches it through Steam, so your application launcher can start it directly:

```nix
{
  programs.steam.config.apps.cyberpunk-2077 = {
    id = 1091500;
    desktopEntry = {
      enable = true;
      # name, comment, icon and categories all have sensible defaults
      name = "Cyberpunk 2077";
    };
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
