---
title: Use DXVK without Winetricks
weight: 16
---

DXVK and VKD3D translate Direct3D to Vulkan. Proton ships both, so most games
need neither. To use a specific version:

## With Winetricks

```nix
{
  programs.steam-config.apps."1234560" = {
    name = "Some Game";
    winetricks = [ "dxvk" ];
  };
}
```

Winetricks will install whatever DXVK release is latest at launch.

## With DLLs from nixpkgs

Serve the DLLs in the prefix and tell Wine to load them over its built-in ones:

```nix
{
  programs.steam-config.apps."1234560" = {
    name = "Some Game";

    files.prefix.overlay = {
      "drive_c/windows/system32/d3d11.dll".source = "${pkgs.dxvk.bin}/x64/d3d11.dll";
      "drive_c/windows/system32/dxgi.dll".source = "${pkgs.dxvk.bin}/x64/dxgi.dll";
    };

    dllOverrides = {
      d3d11 = "n";
      dxgi = "n";
    };
  };
}
```

`"n"` means native: load the DLL that is there rather than Wine's built-in one.

The paths inside the DXVK package and the DLLs a given game needs both vary by
version, so check what your Proton build already provides before adding
anything.

Setting `WINEDLLOVERRIDES` in `env` as well as `dllOverrides` is rejected, so
declare the load order here rather than by hand. See [DLL
overrides]({{< relref "/docs/launch-options#dll-overrides" >}}).
