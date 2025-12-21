## programs\.steam\.config\.enable



Whether to enable declarative Steam configuration\.



*Type:*
boolean



*Default:*
` false `



*Example:*
` true `



## programs\.steam\.config\.package



The steam-config-patcher package to use\.



*Type:*
package



*Default:*
` <derivation steam-config-patcher-0.2.0> `



## programs\.steam\.config\.apps

Configuration per Steam app\.



*Type:*
attribute set of (submodule)



*Default:*
` { } `



*Example:*

````
{
  # App IDs can be provided through the `id` property
  spin-rhythm = {
    id = 1058830;
    launchOptions = "DVXK_ASYNC=1 gamemoderun %command%";
  };

  # Or be provided through the `<name>`
  "620".launchOptions = "-vulkan";
};
````



## programs\.steam\.config\.apps\.\<name>\.compatTool



Compatibility tool to use\.



*Type:*
null or string



*Default:*
` null `



*Example:*
` "proton_experimental" `



## programs\.steam\.config\.apps\.\<name>\.id



The Steam App ID\.

App IDs can be found through the game’s store page URL\.

If an ID is not provided, the app’s ` <name> ` will be used\.



*Type:*
signed integer



*Default:*
` lib.strings.toIntBase10 <name> `



*Example:*
` 438100 `



## programs\.steam\.config\.apps\.\<name>\.launchOptions



The Launch options to use\.

Launch options can be provided as:

**` singleLineStr `**

```nix
''env -u TZ PRESSURE_VESSEL_FILESYSTEMS_RW="$XDG_RUNTIME_DIR/wivrn/comp_ipc" %command% --use-d3d11''
```

**` package `**

```nix
pkgs.writeShellScriptBin "vrchat-wrapper" ''
  export PRESSURE_VESSEL_FILESYSTEMS_RW="$XDG_RUNTIME_DIR/wivrn/comp_ipc"
  unset TZ

  if [[ "$*" == *"-force-vulkan"* ]]; then
    export PROTON_ENABLE_WAYLAND=1
  fi

  exec ${lib.getExe pkgs.gamemode} "''${args[@]}" --use-d3d11
'';
```

**` launchOptionsSubmodule `**

```nix
{
  # Environment variables
  env = {
    PROTON_USE_NTSYNC = true;
    TZ = null; # This unsets the variable
  };

  # Arguments for the game's executable (%command% <...>)
  args = [
    "-force-vulkan"
  ];

  # Programs to wrap the game with (<...> %command%)
  wrappers = [
    (lib.getExe pkgs.gamemode)
    "mangohud"
  ];

  # Extra bash code to run before executing the game
  extraConfig = ''
    if [[ "$*" == *"-force-vulkan"* ]]; then
      export PROTON_ENABLE_WAYLAND=1
    fi
  '';
};
```



*Type:*
null or package or (submodule) or (package or (optionally newline-terminated) single-line string convertible to it)



*Default:*
` null `



*Example:*

```
{
  env.WINEDLLOVERRIDES = "winmm,version=n,b";
  args = [
    "--launcher-skip"
    "-skipStartScreen"
  ];
};
```



## programs\.steam\.config\.apps\.\<name>\.wrapperPath



A stable path outside of the nix store to link the app wrapper script\.



*Type:*
null or absolute path



*Default:*
` ${config.xdg.dataHome}/steam-config-nix/users/<user-id>/app-wrappers/<app-id> `



*Example:*
` "/home/diffy/1361210-wrapper" `



## programs\.steam\.config\.closeSteam



Whether to enable automatic Steam shutdown before writing configuration changes\.



*Type:*
boolean



*Default:*
` false `



*Example:*
` true `



## programs\.steam\.config\.defaultCompatTool



Default compatibility tool to use for Steam Play\.

This option sets the default compatibility tool in Steam, but does not set the nix module defaults\.



*Type:*
null or string



*Default:*
` null `



*Example:*
` "proton_experimental" `



## programs\.steam\.config\.steamDir



Path to the Steam directory\.



*Type:*
absolute path



*Default:*
` ${config.home.homeDirectory}/.steam/steam `



*Example:*
` "/home/diffy/.local/share/Steam" `



## programs\.steam\.config\.users



Configuration per Steam User\.



*Type:*
attribute set of (submodule)



*Default:*
` { } `



*Example:*

```
{
  "12345678987654321" = {
    apps = {
      "620" = {
        launchOptions = "--launcher-skip";
      };
    };
  };
  diffy = {
    apps = {
      "620" = {
        launchOptions = "-vulkan";
      };
    };
    id = 98765432123456789;
  };
}
```



## programs\.steam\.config\.users\.\<name>\.apps



Configuration per Steam app\.



*Type:*
attribute set of (submodule)



*Default:*
` { } `



*Example:*

````
{
  # App IDs can be provided through the `id` property
  spin-rhythm = {
    id = 1058830;
    launchOptions = "DVXK_ASYNC=1 gamemoderun %command%";
  };

  # Or be provided through the `<name>`
  "620".launchOptions = "-vulkan";
};
````



## programs\.steam\.config\.users\.\<name>\.apps\.\<name>\.id



The Steam App ID\.

App IDs can be found through the game’s store page URL\.

If an ID is not provided, the app’s ` <name> ` will be used\.



*Type:*
signed integer



*Default:*
` lib.strings.toIntBase10 <name> `



*Example:*
` 438100 `



## programs\.steam\.config\.users\.\<name>\.apps\.\<name>\.launchOptions



The Launch options to use\.

Launch options can be provided as:

**` singleLineStr `**

```nix
''env -u TZ PRESSURE_VESSEL_FILESYSTEMS_RW="$XDG_RUNTIME_DIR/wivrn/comp_ipc" %command% --use-d3d11''
```

**` package `**

```nix
pkgs.writeShellScriptBin "vrchat-wrapper" ''
  export PRESSURE_VESSEL_FILESYSTEMS_RW="$XDG_RUNTIME_DIR/wivrn/comp_ipc"
  unset TZ

  if [[ "$*" == *"-force-vulkan"* ]]; then
    export PROTON_ENABLE_WAYLAND=1
  fi

  exec ${lib.getExe pkgs.gamemode} "''${args[@]}" --use-d3d11
'';
```

**` launchOptionsSubmodule `**

```nix
{
  # Environment variables
  env = {
    PROTON_USE_NTSYNC = true;
    TZ = null; # This unsets the variable
  };

  # Arguments for the game's executable (%command% <...>)
  args = [
    "-force-vulkan"
  ];

  # Programs to wrap the game with (<...> %command%)
  wrappers = [
    (lib.getExe pkgs.gamemode)
    "mangohud"
  ];

  # Extra bash code to run before executing the game
  extraConfig = ''
    if [[ "$*" == *"-force-vulkan"* ]]; then
      export PROTON_ENABLE_WAYLAND=1
    fi
  '';
};
```



*Type:*
null or package or (submodule) or (package or (optionally newline-terminated) single-line string convertible to it)



*Default:*
` null `



*Example:*

```
{
  env.WINEDLLOVERRIDES = "winmm,version=n,b";
  args = [
    "--launcher-skip"
    "-skipStartScreen"
  ];
};
```



## programs\.steam\.config\.users\.\<name>\.apps\.\<name>\.wrapperPath



A stable path outside of the nix store to link the app wrapper script\.



*Type:*
null or absolute path



*Default:*
` ${config.xdg.dataHome}/steam-config-nix/users/<user-id>/app-wrappers/<app-id> `



*Example:*
` "/home/diffy/1361210-wrapper" `



## programs\.steam\.config\.users\.\<name>\.id



The Steam User ID in SteamID64 or SteamID3 format\.

User IDs can be found through through [https://steamid\.io/lookup](https://steamid\.io/lookup)\.



*Type:*
signed integer



*Default:*
` lib.strings.toIntBase10 <name> `



*Example:*
` 98765432123456789 `


