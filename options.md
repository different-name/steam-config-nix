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
` <derivation steam-config-patcher-0.4.0> `



## programs\.steam\.config\.apps

Configuration per Steam app\.



*Type:*
attribute set of (submodule)



*Default:*
` { } `



*Example:*

```
{
  "Spin Rhythm XD" = {
    id = 1058830;
    launchOptionsStr = "DVXK_ASYNC=1 gamemoderun %command%";
  };
}
```



## programs\.steam\.config\.apps\.\<name>\.enable



Whether to manage this app\.

When false the app is ignored, and any configuration previously applied for it is reverted\.



*Type:*
boolean



*Default:*
` true `



*Example:*
` false `



## programs\.steam\.config\.apps\.\<name>\.artwork\.cover



cover (600x900 portrait) shown in the Steam library\.



*Type:*
null or absolute path



*Default:*
` null `



*Example:*
` ./cover.jpg `



## programs\.steam\.config\.apps\.\<name>\.artwork\.header



header (460x215 horizontal) shown in the Steam library\.



*Type:*
null or absolute path



*Default:*
` null `



*Example:*
` ./header.jpg `



## programs\.steam\.config\.apps\.\<name>\.artwork\.hero



hero (background) shown in the Steam library\.



*Type:*
null or absolute path



*Default:*
` null `



*Example:*
` ./hero.jpg `



## programs\.steam\.config\.apps\.\<name>\.artwork\.logo



logo (transparent overlay) shown in the Steam library\.



*Type:*
null or absolute path



*Default:*
` null `



*Example:*
` ./logo.jpg `



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



Compatibility tool to use, either the internal name of an installed tool (e\.g\. ` "proton_experimental" `), or a package containing one\.

Packages are installed automatically, see the readme for details\.



*Type:*
null or string or package



*Default:*
` null `



*Example:*
` pkgs.proton-ge-bin `



## programs\.steam\.config\.apps\.\<name>\.desktopEntry\.enable



Whether to generate a desktop entry that launches this app through Steam\.

Defaults to the global ` programs.steam.config.desktopEntries.enable ` option\.



*Type:*
boolean



*Default:*
` config.programs.steam.config.desktopEntries.enable `



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
` the app's artwork.icon, or "steam" `



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



## programs\.steam\.config\.apps\.\<name>\.desktopEntry\.useLibraryIcon



Use the app’s own icon from your Steam library for its desktop entry, instead of the generic Steam icon\.

Defaults to the global ` programs.steam.config.desktopEntries.libraryIcons ` option\. Setting ` desktopEntry.icon ` explicitly always takes precedence\.

Has no effect unless ` desktopEntry.enable ` is set\.



*Type:*
boolean



*Default:*
` config.programs.steam.config.desktopEntries.libraryIcons `



*Example:*
` false `



## programs\.steam\.config\.apps\.\<name>\.files\.install



Files to place in the game’s install directory, keyed by path relative to it\. The app must be installed for these to be applied\.



*Type:*
attribute set of (submodule)



*Default:*
` { } `



*Example:*

```
{
  "BepInEx/plugins/plugin.dll".source = ./plugin.dll;
  "mod.cfg" = {
    source = ./mod.cfg;
    overwriteChanges = false;
  };
}

```



## programs\.steam\.config\.apps\.\<name>\.files\.install\.\<name>\.enable



Whether to manage this file\.

When false the file is ignored, and any file previously placed for it is reverted\.



*Type:*
boolean



*Default:*
` true `



## programs\.steam\.config\.apps\.\<name>\.files\.install\.\<name>\.executable



Whether the placed file is executable\.

When null the executable bit is inherited from the source\.



*Type:*
null or boolean



*Default:*
` null `



*Example:*
` true `



## programs\.steam\.config\.apps\.\<name>\.files\.install\.\<name>\.overwriteChanges



Whether to re-apply this file on every activation\.

When true the declared contents are enforced each activation\. When false the file is written once and then left alone, so changes the game or you make to it are preserved\. Delete the file to re-apply\.



*Type:*
boolean



*Default:*
` true `



*Example:*
` false `



## programs\.steam\.config\.apps\.\<name>\.files\.install\.\<name>\.source



File or directory to place\. A directory is copied recursively and merged with whatever is already at the target\.

Exactly one of ` source ` or ` text ` must be set\.



*Type:*
null or absolute path



*Default:*
` null `



*Example:*
` ./mods/plugin.dll `



## programs\.steam\.config\.apps\.\<name>\.files\.install\.\<name>\.target



Path relative to the root, defaulting to the attribute name\.



*Type:*
string



*Default:*
` <name> `



*Example:*
` "BepInEx/plugins/plugin.dll" `



## programs\.steam\.config\.apps\.\<name>\.files\.install\.\<name>\.text



Inline contents to place as a file\.

Exactly one of ` source ` or ` text ` must be set\.



*Type:*
null or strings concatenated with “\\n”



*Default:*
` null `



## programs\.steam\.config\.apps\.\<name>\.files\.prefix



Files to place in the app’s Proton prefix, keyed by path relative to the prefix root (` compatdata/<id>/pfx `)\. The app must have been launched once for the prefix to exist\.



*Type:*
attribute set of (submodule)



*Default:*
` { } `



*Example:*

```
{
  "drive_c/users/steamuser/AppData/Local/game/mod.xml".source = ./mod.xml;
}

```



## programs\.steam\.config\.apps\.\<name>\.files\.prefix\.\<name>\.enable



Whether to manage this file\.

When false the file is ignored, and any file previously placed for it is reverted\.



*Type:*
boolean



*Default:*
` true `



## programs\.steam\.config\.apps\.\<name>\.files\.prefix\.\<name>\.executable



Whether the placed file is executable\.

When null the executable bit is inherited from the source\.



*Type:*
null or boolean



*Default:*
` null `



*Example:*
` true `



## programs\.steam\.config\.apps\.\<name>\.files\.prefix\.\<name>\.overwriteChanges



Whether to re-apply this file on every activation\.

When true the declared contents are enforced each activation\. When false the file is written once and then left alone, so changes the game or you make to it are preserved\. Delete the file to re-apply\.



*Type:*
boolean



*Default:*
` true `



*Example:*
` false `



## programs\.steam\.config\.apps\.\<name>\.files\.prefix\.\<name>\.source



File or directory to place\. A directory is copied recursively and merged with whatever is already at the target\.

Exactly one of ` source ` or ` text ` must be set\.



*Type:*
null or absolute path



*Default:*
` null `



*Example:*
` ./mods/plugin.dll `



## programs\.steam\.config\.apps\.\<name>\.files\.prefix\.\<name>\.target



Path relative to the root, defaulting to the attribute name\.



*Type:*
string



*Default:*
` <name> `



*Example:*
` "BepInEx/plugins/plugin.dll" `



## programs\.steam\.config\.apps\.\<name>\.files\.prefix\.\<name>\.text



Inline contents to place as a file\.

Exactly one of ` source ` or ` text ` must be set\.



*Type:*
null or strings concatenated with “\\n”



*Default:*
` null `



## programs\.steam\.config\.apps\.\<name>\.id



The Steam App ID\. App IDs can be found through the game’s store page URL\.



*Type:*
signed integer



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



Environment variables to export in the launch script\. You can also unset variables by setting their value to ` null `\.



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



## programs\.steam\.config\.apps\.\<name>\.removeFiles\.install



Paths in the game’s install directory to remove, relative to it\. A directory is removed recursively\. Removed files are restored when the entry is unset\.



*Type:*
list of string



*Default:*
` [ ] `



*Example:*

```
[
  "movies/intro.bik"
]
```



## programs\.steam\.config\.apps\.\<name>\.removeFiles\.prefix



Paths in the app’s Proton prefix to remove, relative to the prefix root\.



*Type:*
list of string



*Default:*
` [ ] `



## programs\.steam\.config\.apps\.\<name>\.updateBehavior



How Steam keeps this app updated:

 - ` "always" `: always keep the app updated
 - ` "onLaunch" `: only update the app when it is launched
 - ` "highPriority" `: always update this app before others

The app must be installed for this to be applied\. When unset again, Steam’s default update behaviour is restored\.



*Type:*
null or one of “always”, “onLaunch”, “highPriority”



*Default:*
` null `



*Example:*
` "onLaunch" `



## programs\.steam\.config\.apps\.\<name>\.winetricks



winetricks verbs to install into the app’s Proton prefix\.

Applied when the app is launched (via protontricks, using the prefix and Proton that Steam provides in the environment), and re-applied when the verb list changes\. The app must use a compatibility tool, and must have been launched once so the prefix exists\.

Removing a verb does not uninstall it, as winetricks cannot reliably undo verbs\.



*Type:*
list of string



*Default:*
` [ ] `



*Example:*

```
[
  "vcrun2022"
  "corefonts"
]
```



## programs\.steam\.config\.defaultCompatTool



Default compatibility tool to use for Steam Play, either the internal name of an installed tool, or a package containing one\.

This option sets the default compatibility tool in Steam, but does not set the nix module defaults\.



*Type:*
null or string or package



*Default:*
` null `



*Example:*
` "proton_experimental" `



## programs\.steam\.config\.desktopEntries



Desktop entry defaults for all configured apps\.

Setting this to a boolean is deprecated; use ` desktopEntries.enable ` instead\. Individual apps can opt out with ` desktopEntry.enable = false `\.



*Type:*
(submodule) or boolean convertible to it



*Default:*
` { } `



*Example:*

```
{
  enable = true;
}
```



## programs\.steam\.config\.desktopEntries\.enable



Whether to enable desktop entries for all configured apps by default\.



*Type:*
boolean



*Default:*
` false `



*Example:*
` true `



## programs\.steam\.config\.desktopEntries\.libraryIcons



Use each Steam app’s own icon from your Steam library for its desktop entry, instead of the generic Steam icon\.

Icons are taken from Steam’s local library cache, so an app must have been seen by Steam at least once for its icon to be available\. They are small (typically 32x32), and fall back to the Steam icon when they cannot be resolved\.

Individual apps can opt out with ` desktopEntry.useLibraryIcon = false `, and setting ` desktopEntry.icon ` explicitly always takes precedence\.



*Type:*
boolean



*Default:*
` true `



*Example:*
` false `



## programs\.steam\.config\.nonSteamApps



Configuration per non-Steam app\.



*Type:*
attribute set of (submodule)



*Default:*
` { } `



*Example:*

```
{
  "Vintage Story" = {
    # target is the executable, accepts a package or a path
    target = pkgs.vintagestory;
  };

  "Some Game" = {
    target = "/home/alice/Games/some-game/start";
    artwork.icon = ./some-game.png;
    compatTool = "proton_experimental";
    launchOptionsStr = "gamemoderun %command%";
  };
}
```



## programs\.steam\.config\.nonSteamApps\.\<name>\.enable



Whether to manage this app\.

When false the app is ignored, and any configuration previously applied for it is reverted\.



*Type:*
boolean



*Default:*
` true `



*Example:*
` false `



## programs\.steam\.config\.nonSteamApps\.\<name>\.allowOverlay



Whether this app should have the steam overlay\.



*Type:*
boolean



*Default:*
` true `



*Example:*
` false `



## programs\.steam\.config\.nonSteamApps\.\<name>\.artwork\.cover



cover (600x900 portrait) shown in the Steam library\.



*Type:*
null or absolute path



*Default:*
` null `



*Example:*
` ./cover.jpg `



## programs\.steam\.config\.nonSteamApps\.\<name>\.artwork\.header



header (460x215 horizontal) shown in the Steam library\.



*Type:*
null or absolute path



*Default:*
` null `



*Example:*
` ./header.jpg `



## programs\.steam\.config\.nonSteamApps\.\<name>\.artwork\.hero



hero (background) shown in the Steam library\.



*Type:*
null or absolute path



*Default:*
` null `



*Example:*
` ./hero.jpg `



## programs\.steam\.config\.nonSteamApps\.\<name>\.artwork\.icon



Icon shown in the taskbar and shortcut list\.



*Type:*
null or absolute path



*Default:*
` null `



*Example:*
` ./icon.png `



## programs\.steam\.config\.nonSteamApps\.\<name>\.artwork\.logo



logo (transparent overlay) shown in the Steam library\.



*Type:*
null or absolute path



*Default:*
` null `



*Example:*
` ./logo.jpg `



## programs\.steam\.config\.nonSteamApps\.\<name>\.compatTool



Compatibility tool to use, either the internal name of an installed tool (e\.g\. ` "proton_experimental" `), or a package containing one\.

Packages are installed automatically, see the readme for details\.



*Type:*
null or string or package



*Default:*
` null `



*Example:*
` pkgs.proton-ge-bin `



## programs\.steam\.config\.nonSteamApps\.\<name>\.desktopEntry\.enable



Whether to generate a desktop entry that launches this app through Steam\.

Defaults to the global ` programs.steam.config.desktopEntries.enable ` option\.



*Type:*
boolean



*Default:*
` config.programs.steam.config.desktopEntries.enable `



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
` the app's artwork.icon, or "steam" `



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



Environment variables to export in the launch script\. You can also unset variables by setting their value to ` null `\.



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



## programs\.steam\.config\.nonSteamApps\.\<name>\.winetricks



winetricks verbs to install into the app’s Proton prefix\.

Applied when the app is launched (via protontricks, using the prefix and Proton that Steam provides in the environment), and re-applied when the verb list changes\. The app must use a compatibility tool, and must have been launched once so the prefix exists\.

Removing a verb does not uninstall it, as winetricks cannot reliably undo verbs\.



*Type:*
list of string



*Default:*
` [ ] `



*Example:*

```
[
  "vcrun2022"
  "corefonts"
]
```



## programs\.steam\.config\.notifications



Send desktop notifications for slow launch-time steps (e\.g\. installing winetricks verbs)\.

Degrades gracefully: if no notification daemon is reachable the notification is simply skipped\.



*Type:*
boolean



*Default:*
` true `



*Example:*
` false `



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


