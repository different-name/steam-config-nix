---
title: Patch a Unity game's settings
weight: 22
---

Unity games store their per-user settings in PlayerPrefs. On Windows (and so
inside a Proton prefix) that means the registry, under
`Software\<Company>\<Product>`, with a hash appended to each key name and the
value encoded in a Unity-specific way.

The `unityPrefs` format handles both, so you write the plain key name:

```nix
{
  programs.steam.config.apps."438100" = {
    name = "VRChat";
    files.prefix.patch."user.reg" = {
      format = "unityPrefs";
      content."Software/VRChat/VRChat" = {
        VRC_MAX_PARTICLE_SYSTEMS = 100;
      };
    };
  };
}
```

`content` maps a registry path to plain PlayerPrefs keys and values. Integers,
floats, booleans and strings are each encoded the way Unity expects.

The key path may use `/` or `\\` as the separator, so `"Software/VRChat/VRChat"`
and `"Software\\VRChat\\VRChat"` are equivalent.

## Finding the company and product

They come from the game's own build settings, not from its Steam name. The
reliable way to find them is to launch the game once, then look at what appeared
under `Software\` in the prefix's `user.reg`.

## Raw registry access

If you need a registry value that is not a PlayerPref, use the `registry` format
instead. It maps a key path to value names directly, where a string becomes a
`REG_SZ` and an integer a `REG_DWORD`:

```nix
{
  programs.steam.config.apps."1234560" = {
    name = "Some Game";
    files.prefix.patch."user.reg" = {
      format = "registry";
      content."Software/Wine/DllOverrides".mfplat = "native";
    };
  };
}
```

## How the keys reach the game

`patch` merges your keys into the game's own file on activation. Only the keys
you name are touched, and the original is backed up before the first write, so
removing the entry restores it.
