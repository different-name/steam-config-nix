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

Then import and enable the [Home Manager](https://github.com/nix-community/home-manager) module

```nix
imports = [
  inputs.steam-config-nix.homeModules.default
];

programs.steam.config = {
  enable = true;
};
```

## Usage

Configuration is applied per Steam user ID

User IDs must be in `steamID3` format **without** `[]` or the `U:1:` prefix. For example: `[U:1:987654321]` -> `987654321`

You can find your Steam ID through [steamid.io/lookup](https://steamid.io/lookup) or in `~/.steam/steam/userdata`

### Setting launch options

Define launch options per App ID using:

```
programs.steam.config.users.<user_id>.launchOptions.<app_id>
```

You can find a game's AppID using [steamdb.info](https://steamdb.info/) or through the game’s store page URL

#### Example

```nix
programs.steam.config = {
  enable = true;
  closeSteam = true; # See 'Important' note at beginning of this readme

  users."987654321" = {
    launchOptions = {
      "438100" = ''env -u TZ PRESSURE_VESSEL_FILESYSTEMS_RW="$XDG_RUNTIME_DIR/wivrn/comp_ipc" %command%'';
      "620" = ''%command% -vulkan'';
    };
  };
};
```

### Extra config

Set any `config.vdf` or `localconfig.vdf` value using:

```
programs.steam.config.users.<user_id>.extraConfig
programs.steam.config.users.<user_id>.extraLocalConfig
```

I am not sure what practical applications this has yet, but it is included for completeness

#### Example

```nix
programs.steam.config = {
  enable = true;
  closeSteam = true; # See 'Important' note at beginning of this readme

  users."987654321" = {
    extraConfig = {
      InstallConfigStore.Software.Valve.Steam = {
        CompatToolMapping = {
          "438100" = {
						name = "proton_experimental";
						config = "";
						priority = "250";
					};
        };
      };
    };

    extraLocalConfig = {
      UserLocalConfigStore.Software.Valve.Steam = {
        Apps = {
          "438100" = {
            LaunchOptions = ''env -u TZ PRESSURE_VESSEL_FILESYSTEMS_RW="$XDG_RUNTIME_DIR/wivrn/comp_ipc" %command%'';
          };
          "620" = {
            LaunchOptions = ''%command% -vulkan'';
          };
        };
      };
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
    export PRESSURE_VESSEL_FILESYSTEMS_RW="$XDG_RUNTIME_DIR/wivrn/comp_ipc"
    unset TZ
  '';
};
```

## Goals

- Beta config

## Acknowledgements

- https://github.com/FeralInteractive/gamemode/issues/177 for the idea
- https://github.com/TeamSpen210/srctools for their library
