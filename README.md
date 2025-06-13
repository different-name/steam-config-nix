# steam-launch.nix

Home Manager module for declarative Steam game launch options

> [!WARNING]
> This module is in early development, it is unstable and should be treated as such
> 
> Please report bugs and request features in the [issues tab](https://github.com/different-name/steam-launch.nix/issues)

## Usage

### Flakes

Import the [home-manager](https://github.com/nix-community/home-manager) module

```nix
{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    steam-launch-nix = {
      url = "github:different-name/steam-launch.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, catppuccin, home-manager }: {
    # for nixos module home-manager installations
    nixosConfigurations.diffysComputer = pkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        home-manager.nixosModules.home-manager
        {
          home-manager.users.diffy = {
            imports = [
              ./home.nix
              steam-launch-nix.homeModules.steam-launch
            ];
          };
        }
      ];
    };

    # for standalone home-manager installations
    homeConfigurations.sodium = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      modules = [
        ./home.nix
        steam-launch-nix.homeModules.steam-launch
      ];
    };
  };
}
```

### Configuration

In your configuration, enable the module

```nix
programs.steam-launch = {
  enable = true;
};
```

and configure your launch options, here's an example

```nix
programs.steam-launch = {
  enable = true;
  
  options = {
    "438100" = ''env -u TZ PRESSURE_VESSEL_FILESYSTEMS_RW="$XDG_RUNTIME_DIR/wivrn/comp_ipc" %command%'';
    "620" = "%command% -vulkan";
  };
};
```

#### Global Configuration

This module only provides per-game launch options

You can set to environmental variables across all games by overriding `extraProfile` in the steam package like so:

```nix
programs.steam.package = pkgs.steam.override {
  extraProfile = ''
    export PRESSURE_VESSEL_FILESYSTEMS_RW="$XDG_RUNTIME_DIR/wivrn/comp_ipc"
    unset TZ
  '';
};
```

## Acknowledgements

- https://github.com/FeralInteractive/gamemode/issues/177 for the idea
- https://github.com/TeamSpen210/srctools for their library
- https://github.com/catppuccin/nix for the README usage example