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
` <derivation steam-config-patcher-0.2.3> `



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
}
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



App launch options, see example for usage\.

If ` launchOptionsStr ` is defined, that will be used instead\.



*Type:*
null or (submodule) or (optionally newline-terminated) single-line string or package



*Default:*
` null `



*Example:*

````
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

  /*
    Extra bash code to run before executing the game
    These variables are available in scope for you to read / modify in this hook:
      `wrappers`: values from the wrappers option
      `game_command`: the %command% passed from steam
      `args`: values from the args option
  */
  preHook = ''
    if [[ "$*" == *"-force-vulkan"* ]]; then
      export PROTON_ENABLE_WAYLAND=1
    fi

    for i in "''${!game_command[@]}"; do
      game_command[i]="''${game_command[i]//\/Launcher.exe/\/game.exe}"
    done
  '';
};
````



## programs\.steam\.config\.apps\.\<name>\.launchOptionsStr



Traditional Steam launch options\.

If this is defined it will be used instead of the ` launchOption ` option\.



*Type:*
null or (optionally newline-terminated) single-line string



*Default:*
` null `



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


