# steam-confg-nix

Manage Steam launch options and other local config declaratively through [Home Manager](https://github.com/nix-community/home-manager)

> [!WARNING]
> This flake is in early development and may be unstable
> 
> Please report bugs or request features via the [issues tab](https://github.com/different-name/steam-launch.nix/issues)


> [!IMPORTANT]  
> **Steam must be closed** when activating your Home Manager configuration, this is because steam configuration files can only be written to reliably while Steam is not running
>
> If `programs.steam.config.closeSteam` is enabled, Steam will be closed before writing changes. Steam won't be closed if configuration values have not changed

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

```nix
programs.steam.config = {
  enable = true;
  closeSteam = true; # see 'Important' note at beginning of this readme

  # Configuration for apps across all users
  apps = {
    # App IDs can be found through the game's store URL
    "438100" = {
      # Compat tool names can be found in ~/.steam/steam/config/config.vdf under "CompatToolMapping"
      compatTool = "proton_experimental";
    };

    "1058830" = {
      compatTool = "GE-Proton";
      launchOptions = "DVXK_ASYNC=1 gamemoderun %command%";
    };
  }

  # Configuration per user's steamID3
  # Your steamID3 can be found using https://steamid.io/lookup or in ~/.steam/steam/userdata
  users."987654321".apps = {
    # Per user config only supports launchOptions
    # Pompat tools must be set globally
    "438100".launchOptions = ''env -u TZ PRESSURE_VESSEL_FILESYSTEMS_RW="$XDG_RUNTIME_DIR/wivrn/comp_ipc" %command%'';
    "620".launchOptions = "%command% -vulkan";
  };
};
```

### Global Configuration

It is not possible to perform any global configuration of games through Steam configuration

To set environment variables for all Steam games, override `extraProfile` in the Steam package:

```nix
programs.steam.package = pkgs.steam.override {
  extraProfile = ''
    export PRESSURE_VESSEL_FILESYSTEMS_RW="$XDG_RUNTIME_DIR/wivrn/comp_ipc"
    unset TZ
  '';
};
```

## Goals

- Beta config
- Add non steam games

## Acknowledgements

- https://github.com/FeralInteractive/gamemode/issues/177 for the idea
- https://github.com/TeamSpen210/srctools for their library
