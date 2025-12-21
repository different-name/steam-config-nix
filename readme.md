# steam-config-nix

Manage Steam launch options and compatibility tools declaratively through [Home Manager](https://github.com/nix-community/home-manager)

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

Then import the [Home Manager](https://github.com/nix-community/home-manager) module

```nix
imports = [
  inputs.steam-config-nix.homeModules.default
];
```

## Usage

See [options.md](options.md) for all available options

#### Quickstart example

```nix
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
  };

  users.diffy = {
    id = 12345678987654321;
    apps.vrchat = {
      id = 438100;
      launchOptions.env.TZ = null;
    };
  };
};
```

### Global Configuration

It is not possible to perform any global configuration of games through Steam configuration

To set environment variables for all Steam games, override `extraProfile` in the Steam package:

```nix
programs.steam.package = pkgs.steam.override {
  extraProfile = ''
    export PROTON_ENABLE_WAYLAND=1
    export PRESSURE_VESSEL_FILESYSTEMS_RW="$XDG_RUNTIME_DIR/wivrn/comp_ipc"
    unset TZ
  '';
};
```

## Acknowledgements

- https://github.com/FeralInteractive/gamemode/issues/177 for the idea
- https://github.com/TeamSpen210/srctools for their library
