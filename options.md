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
` <derivation steam-config-patcher-0.2.4> `



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
    launchOptionsStr = "DVXK_ASYNC=1 gamemoderun %command%";
  };

  # Or be provided through the `<name>`
  "620".launchOptionsStr = "-vulkan";
}
````



## programs\.steam\.config\.apps\.\<name>\.betaBranch



Beta branch to opt this app into\.

The app must be installed for this to be applied, Steam will download the branch’s build on its next start\.

When unset again, the app is reverted to the default branch\.



*Type:*
null or string



*Default:*
` null `



*Example:*
` "prerelease" `



## programs\.steam\.config\.apps\.\<name>\.compatTool



Compatibility tool to use, either the internal name of an installed
tool (e\.g\. ` "proton_experimental" `), or a package containing one\.

Packages are installed automatically, see the readme for details\.



*Type:*
null or string or package



*Default:*
` null `



*Example:*
` pkgs.proton-ge-bin `



## programs\.steam\.config\.apps\.\<name>\.desktopEntry\.enable



Whether to generate a desktop entry that launches this app through Steam\.

Defaults to the global ` programs.steam.config.desktopEntries ` option\.



*Type:*
boolean



*Default:*
` config.programs.steam.config.desktopEntries `



*Example:*
` true `



## programs\.steam\.config\.apps\.\<name>\.desktopEntry\.categories



Freedesktop categories for the desktop entry\.



*Type:*
list of string



*Default:*

```
[
  "Game"
]
```



## programs\.steam\.config\.apps\.\<name>\.desktopEntry\.comment



Tooltip comment for the desktop entry\.



*Type:*
string



*Default:*
` "Launch ${config.desktopEntry.name} with Steam" `



## programs\.steam\.config\.apps\.\<name>\.desktopEntry\.genericName



Generic name for the desktop entry\.



*Type:*
null or string



*Default:*
` null `



*Example:*
` "Role Playing Game" `



## programs\.steam\.config\.apps\.\<name>\.desktopEntry\.icon



Icon for the desktop entry, an icon name or image file\.



*Type:*
null or string or absolute path



*Default:*
` "steam" `



*Example:*
` ./icon.png `



## programs\.steam\.config\.apps\.\<name>\.desktopEntry\.name



Name shown for the desktop entry\.



*Type:*
string



*Default:*
` <name> `



*Example:*
` "Cyberpunk 2077" `



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



## programs\.steam\.config\.apps\.\<name>\.language



Language to use for this app, as a Steam API language name (e\.g\. ` "english" `, ` "german" `, ` "schinese" `)\.

The app must be installed for this to be applied, Steam will download the language’s depots on its next start\.

When unset again, Steam reverts to its default language for the app\.



*Type:*
null or string



*Default:*
` null `



*Example:*
` "german" `



## programs\.steam\.config\.apps\.\<name>\.launchOptions\.args



Arguments to pass to the game\.



*Type:*
list of string



*Default:*
` [ ] `



*Example:*

```
[
  "-modded"
  "--launcher-skip"
  "-skipStartScreen"
]

```



## programs\.steam\.config\.apps\.\<name>\.launchOptions\.env



Environment variables to export in the launch script\.
You can also unset variables by setting their value to ` null `\.



*Type:*
lazy attribute set of (null or string or absolute path or signed integer or floating point number or boolean)



*Default:*
` { } `



*Example:*

```
{
  WINEDLLOVERRIDES = "winmm,version=n,b";
  TZ = null;
}

```



## programs\.steam\.config\.apps\.\<name>\.launchOptions\.preHook



Extra bash code to run before executing the game

These variables are available in scope for you to read / modify in this hook:

 - ` wrappers `: values from the wrappers option
 - ` game_command `: the %command% passed from steam
 - ` args `: values from the args option



*Type:*
strings concatenated with “\\n”



*Default:*
` "" `



*Example:*

```
''
  if [[ "$*" == *"-force-vulkan"* ]]; then
    export PROTON_ENABLE_WAYLAND=1
  fi
  
  for i in "''${!game_command[@]}"; do
    game_command[i]="''${game_command[i]//\/Launcher.exe/\/game.exe}"
  done
''
```



## programs\.steam\.config\.apps\.\<name>\.launchOptions\.wrappers



Executables to wrap the game with\.



*Type:*
list of (string or package convertible to it)



*Default:*
` [ ] `



*Example:*

```
[
  (lib.getExe' pkgs.mangohud "mangohud")
  pkgs.myWrapperProgram
  "gamemoderun"
]

```



## programs\.steam\.config\.apps\.\<name>\.launchOptionsStr



Traditional Steam launch options\.

Cannot be combined with ` launchOptions `\.



*Type:*
null or (optionally newline-terminated) single-line string



*Default:*
` null `



## programs\.steam\.config\.defaultCompatTool



Default compatibility tool to use for Steam Play, either the internal
name of an installed tool, or a package containing one\.

This option sets the default compatibility tool in Steam, but does not set the nix module defaults\.



*Type:*
null or string or package



*Default:*
` null `



*Example:*
` "proton_experimental" `



## programs\.steam\.config\.desktopEntries



Whether to enable desktop entries for all configured apps by default

Individual apps can opt out with ` desktopEntry.enable = false `\.



*Type:*
boolean



*Default:*
` false `



*Example:*
` true `



## programs\.steam\.config\.nonSteamApps



Configuration per non-Steam app\.



*Type:*
attribute set of (submodule)



*Default:*
` { } `



*Example:*

```
{
  vintage-story = {
    # target is the executable, accepts a package or a path
    target = pkgs.vintagestory;
    # name defaults to the attribute name.
    name = "Vintage Story";
  };

  some-game = {
    target = "/home/alice/Games/some-game/start";
    icon = ./some-game.png;
    compatTool = "proton_experimental";
    launchOptionsStr = "gamemoderun %command%";
  };
}
```



## programs\.steam\.config\.nonSteamApps\.\<name>\.allowOverlay



Whether this app should have the steam overlay\.



*Type:*
boolean



*Default:*
` true `



*Example:*
` false `



## programs\.steam\.config\.nonSteamApps\.\<name>\.compatTool



Compatibility tool to use, either the internal name of an installed
tool (e\.g\. ` "proton_experimental" `), or a package containing one\.

Packages are installed automatically, see the readme for details\.



*Type:*
null or string or package



*Default:*
` null `



*Example:*
` pkgs.proton-ge-bin `



## programs\.steam\.config\.nonSteamApps\.\<name>\.desktopEntry\.enable



Whether to generate a desktop entry that launches this app through Steam\.

Defaults to the global ` programs.steam.config.desktopEntries ` option\.



*Type:*
boolean



*Default:*
` config.programs.steam.config.desktopEntries `



*Example:*
` true `



## programs\.steam\.config\.nonSteamApps\.\<name>\.desktopEntry\.categories



Freedesktop categories for the desktop entry\.



*Type:*
list of string



*Default:*

```
[
  "Game"
]
```



## programs\.steam\.config\.nonSteamApps\.\<name>\.desktopEntry\.comment



Tooltip comment for the desktop entry\.



*Type:*
string



*Default:*
` "Launch ${config.desktopEntry.name} with Steam" `



## programs\.steam\.config\.nonSteamApps\.\<name>\.desktopEntry\.genericName



Generic name for the desktop entry\.



*Type:*
null or string



*Default:*
` null `



*Example:*
` "Role Playing Game" `



## programs\.steam\.config\.nonSteamApps\.\<name>\.desktopEntry\.icon



Icon for the desktop entry, an icon name or image file\.



*Type:*
null or string or absolute path



*Default:*
` "steam" `



*Example:*
` ./icon.png `



## programs\.steam\.config\.nonSteamApps\.\<name>\.desktopEntry\.name



Name shown for the desktop entry\.



*Type:*
string



*Default:*
` <name> `



*Example:*
` "Cyberpunk 2077" `



## programs\.steam\.config\.nonSteamApps\.\<name>\.icon



Image file to use as icon



*Type:*
null or absolute path



*Default:*
` null `



*Example:*
` ./icon.png `



## programs\.steam\.config\.nonSteamApps\.\<name>\.id



The Steam App ID\.

App IDs can be found through the game’s store page URL\.

If an ID is not provided, the app’s ` <name> ` will be used\.



*Type:*
integer between 2147483648 and 4294967295 (both inclusive)



*Default:*
` seedToId config.seed `



*Example:*
` 438100 `



## programs\.steam\.config\.nonSteamApps\.\<name>\.inVrLibrary



Whether this app is a VR app\.



*Type:*
boolean



*Default:*
` false `



*Example:*
` true `



## programs\.steam\.config\.nonSteamApps\.\<name>\.isHidden



Whether this app should be hidden\.



*Type:*
boolean



*Default:*
` false `



*Example:*
` true `



## programs\.steam\.config\.nonSteamApps\.\<name>\.launchOptions\.args



Arguments to pass to the game\.



*Type:*
list of string



*Default:*
` [ ] `



*Example:*

```
[
  "-modded"
  "--launcher-skip"
  "-skipStartScreen"
]

```



## programs\.steam\.config\.nonSteamApps\.\<name>\.launchOptions\.env



Environment variables to export in the launch script\.
You can also unset variables by setting their value to ` null `\.



*Type:*
lazy attribute set of (null or string or absolute path or signed integer or floating point number or boolean)



*Default:*
` { } `



*Example:*

```
{
  WINEDLLOVERRIDES = "winmm,version=n,b";
  TZ = null;
}

```



## programs\.steam\.config\.nonSteamApps\.\<name>\.launchOptions\.preHook



Extra bash code to run before executing the game

These variables are available in scope for you to read / modify in this hook:

 - ` wrappers `: values from the wrappers option
 - ` game_command `: the %command% passed from steam
 - ` args `: values from the args option



*Type:*
strings concatenated with “\\n”



*Default:*
` "" `



*Example:*

```
''
  if [[ "$*" == *"-force-vulkan"* ]]; then
    export PROTON_ENABLE_WAYLAND=1
  fi
  
  for i in "''${!game_command[@]}"; do
    game_command[i]="''${game_command[i]//\/Launcher.exe/\/game.exe}"
  done
''
```



## programs\.steam\.config\.nonSteamApps\.\<name>\.launchOptions\.wrappers



Executables to wrap the game with\.



*Type:*
list of (string or package convertible to it)



*Default:*
` [ ] `



*Example:*

```
[
  (lib.getExe' pkgs.mangohud "mangohud")
  pkgs.myWrapperProgram
  "gamemoderun"
]

```



## programs\.steam\.config\.nonSteamApps\.\<name>\.launchOptionsStr



Traditional Steam launch options\.

Cannot be combined with ` launchOptions `\.



*Type:*
null or (optionally newline-terminated) single-line string



*Default:*
` null `



## programs\.steam\.config\.nonSteamApps\.\<name>\.name



Name to give this app\.



*Type:*
(optionally newline-terminated) single-line string



*Default:*
` "‹name›" `



*Example:*
` "Vintage Story" `



## programs\.steam\.config\.nonSteamApps\.\<name>\.seed



The seed used to generate the app’s ID\.

Seeds are used to generate apps IDs\. And so shouldn’t be changed once the app has been added\.

Changing an app ID for a Wine/Proton game will result in a new Wine prefix being created\.



*Type:*
string



*Default:*
` <name> `



*Example:*
` "vintage-story" `



## programs\.steam\.config\.nonSteamApps\.\<name>\.startIn



Directory to start this app in\.



*Type:*
null or absolute path



*Default:*
` dirOf config.target `



## programs\.steam\.config\.nonSteamApps\.\<name>\.target



Executable for the app, either a package or absolute path\.



*Type:*
absolute path or package convertible to it



*Example:*
` pkgs.vintagestory `



## programs\.steam\.config\.onSteamRunning



What to do when configuration changes need to be written while Steam is running:

 - ` "wait" `: wait for Steam to exit, then apply the changes
 - ` "close" `: close Steam and apply the changes, waiting for any running games to exit first
 - ` "force-close" `: close Steam and apply the changes immediately, even if a game is running
 - ` "skip" `: skip writing, changes will be applied on the next activation



*Type:*
one of “wait”, “close”, “force-close”, “skip”



*Default:*
` "wait" `



*Example:*
` "close" `


