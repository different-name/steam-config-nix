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

```nix
programs.steam.config = {
  enable = true;
  closeSteam = true; # See 'Important' note at beginning of this readme

  # Configuration for apps across all users
  apps = {
    # App IDs can be found through the game's store URL
    "438100" = {
      # Compat tool names can be found in ~/.steam/steam/config/config.vdf under  "CompatToolMapping"
      compatTool = "proton_experimental";
    };

    spin-rhythm = {
      # The id property can be used instead of using the app ID as the key
      id = 1058830;
      compatTool = "GE-Proton";
      launchOptions = "DVXK_ASYNC=1 gamemoderun %command%";
    };
  }

  # Configuration per user's SteamID64
  # You can find your SteamID64 through https://steamid.io/lookup
  users = {
    "98765432123456789".apps = {
      # Per user config only supports launchOptions, compat tools must be set globally
      "438100".launchOptions = ''env -u TZ PRESSURE_VESSEL_FILESYSTEMS_RW="$XDG_RUNTIME_DIR/wivrn/comp_ipc" %command%'';


      # You can also use abstracted Nix options
      "553850".launchOptions = {
        # Environment variables to export
        env = {
          PROTON_USE_NTSYNC = true;
          # This unsets the variable
          TZ = null;
        };
        # Arguments for the game's executable (%command% <...>)
        args = [
          "-force-vulkan"
          "--use-d3d11"
          "+connect_lobby"
          "-1"
        ];
        # Programs to wrap the game with (<...> %command%)
        wrappers = [
          (lib.getExe' pkgs.mangohud "mangohud")
          "gamemoderun"
        ];
        # Extra bash code to run before executing the game
        extraConfig = ''
          if [[ "$*" == *"-force-vulkan"* ]]; then
            export PROTON_ENABLE_WAYLAND=1
          fi
        '';
      };

      "1144200".launchOptions.env.WINEDLLOVERRIDES = "d3dcompiler_47=n;dxgi=n";

      # you can also use a package instead of a string, %command% will be passed to it
      # here's an example script that skips the Warhammer 40k Darktide launcher
      "1361210".launchOptions = pkgs.writeShellScriptBin "darktide-wrapper" ''
        args=()
        for arg in "$@"; do
          args+=( "''${arg//\/launcher\/Launcher.exe/\/binaries\/Darktide.exe}" )
        done

        exec "''${args[@]}"
      '';
    };
  };

  diffy = {
    # The id property can be used instead of using the user ID as the key
    id = 12345678987654321;
    apps = {
      "620".launchOptions = "-vulkan";
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
