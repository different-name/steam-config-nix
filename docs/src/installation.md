# Installation

Add `steam-config-nix` to your flake inputs:

```nix
steam-config-nix = {
  url = "github:different-name/steam-config-nix";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

`steam-config-nix` provides both NixOS and [Home Manager](https://github.com/nix-community/home-manager) modules.

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

Set `programs.steam.config.enable = true` to turn it on, then configure your apps. See the [Quickstart](./quickstart.md) for a working example.
