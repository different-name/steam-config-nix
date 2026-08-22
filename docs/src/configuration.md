# Configuration

Module-wide options that control how steam-config-nix behaves. Per-app options live in their own guides.

Turn the module on with `programs.steam.config.enable = true`, then configure your apps.

## Applying changes

`onSteamRunning` controls what happens when changes need to be written while Steam is running:

- `"wait"` (default): wait for Steam to exit, then apply
- `"close"`: close Steam and apply, waiting for any running game to exit first
- `"force-close"`: close Steam and apply immediately, even mid-game
- `"skip"`: skip writing, changes apply on the next activation

## Notifications

`notifications` (default `true`) sends a desktop notification for slow launch-time steps, such as installing winetricks verbs. If no notification daemon is reachable, the notification is skipped.

## Desktop entries

`desktopEntries.enable` (default `false`) gives every configured app a desktop entry, instead of turning them on one app at a time with `desktopEntry.enable`. `desktopEntries.libraryIcons` (default `true`) uses each Steam app's own icon from your library rather than the generic Steam icon.

Both of these set the default for every app, and each app can still override them. See [Desktop Entries](./desktop-entries.md) for the per-app options.

## Steam Client Options

Options that configure the Steam client itself.

### Download rates

`displayRatesAsBits` sets the units Steam displays download speeds in. Set it to `false` for MB/s and `true` for Mb/s. Left unset, Steam keeps whatever it is already using.
