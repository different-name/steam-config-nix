# steam-config-nix

Manage Steam launch options, compat tools and other local config declaratively through your nix config

> [!WARNING]
> This flake is in early development and may be unstable
>
> Please report bugs or request features via the [issues tab](https://github.com/different-name/steam-launch.nix/issues)

> [!IMPORTANT]  
> **Steam must be closed** when writing to the Steam config files, either close Steam manually before activating your configuration, or enable `programs.steam.config.closeSteam` to close Steam on activation
>
> With this option, Steam will not be closed unless a new game is configured or a compatibility tool is changed

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
    closeSteam = true;
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

      "620" = {
        # Drop files into the install dir or Proton prefix. Backups of
        # replaced files land next to the original with a
        # `.steam-config-nix-backup` suffix on first apply.
        files = {
          # Stub a file with empty content.
          "path/to/intro.bik".empty = true;
          # First-apply config the in-game overlay edits in place.
          "some-config.ini" = {
            source = ./some-config.ini;
            mode = "init";
          };
        };
      };
    };
  };
}
```

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
- https://github.com/TeamSpen210/srctools for their library
