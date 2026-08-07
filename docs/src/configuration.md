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
