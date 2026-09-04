---
title: Use DXVK without Winetricks
weight: 16
---

DXVK and VKD3D translate Direct3D to Vulkan. Modern Proton comes with them so
most games don't need this set up. However, when you do need a specific version,
there are two routes with the same result and different reproducibility.

## The easy, impure route

```nix
{
  programs.steam.config.apps."1234560" = {
    name = "Some Game";
    winetricks = [ "dxvk" ];
  };
}
```

Winetricks downloads the runtime at launch. Simple, and not reproducible.

## The pure route

DXVK is a set of DLLs plus an instruction to Wine to prefer them over its
built-in implementations. Both halves can be declared:

```nix
{
  programs.steam.config.apps."1234560" = {
    name = "Some Game";

    files.prefix.place = {
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
declare the load order here rather than by hand. See [Why dllOverrides
exists]({{< relref "/docs/launch-options#why-dlloverrides-exists" >}}).
