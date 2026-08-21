{
  lib,
  pkgs,
  dataDir,
}:
{
  name,
  config,
  steamConfig,
  ...
}:
let
  # modified from home-manager lib.shell.exportAll
  # https://github.com/nix-community/home-manager/blob/89c9508bbe9b40d36b3dc206c2483ef176f15173/modules/lib/shell.nix#L36-L42
  exportUnset = n: v: if v == null then "unset ${n}" else ''export ${n}="${toString v}"'';
  exportAll = lib.concatMapAttrsStringSep "\n" exportUnset;

  # Steam's launch runtime sets LD_LIBRARY_PATH/LD_PRELOAD to libs that clash
  # with notify-send, so run it with a clean loader environment
  notify =
    body:
    lib.optionalString steamConfig.notifications ''( unset LD_LIBRARY_PATH LD_PRELOAD; ${lib.getExe' pkgs.libnotify "notify-send"} -a steam-config-nix "steam-config-nix" "${body}" ) >/dev/null 2>&1 || true'';

  mkAppWrapperPackage =
    app:
    let
      hasOptions =
        app.env != { }
        || app.wrappers != [ ]
        || app.args != [ ]
        || app.preHook != ""
        || app.dllOverrides != { }
        || app.systemd.enable;
      hasRaw = app.rawLaunchOptions != null;
      hasWinetricks = app.winetricks != [ ];

      # runs before the game, when Steam has set STEAM_COMPAT_* in the environment
      # marker keyed on the verb list so it only runs when the verbs change
      winetricksStep = lib.optionalString hasWinetricks ''
        if [ -n "''${STEAM_COMPAT_DATA_PATH:-}" ] && [ -d "$STEAM_COMPAT_DATA_PATH/pfx" ]; then
          marker="$STEAM_COMPAT_DATA_PATH/steam-config-nix-winetricks"
          want=${lib.escapeShellArg (lib.concatStringsSep " " app.winetricks)}
          if [ "$(cat "$marker" 2>/dev/null)" != "$want" ]; then
            echo "steam-config-nix: applying winetricks verbs: $want"
            ${notify "Installing winetricks: $want..."}
            if ${lib.getExe' pkgs.protontricks "protontricks"} "''${STEAM_COMPAT_APP_ID}" -q ${lib.escapeShellArgs app.winetricks}; then
              printf '%s' "$want" > "$marker"
              ${notify "winetricks installed: $want"}
            else
              echo "steam-config-nix: winetricks failed, continuing to launch" >&2
              ${notify "winetricks failed for app ${toString app.id}"}
            fi
          fi
        fi
      '';

      # steam appends a launch string with no %command% as args to the game
      effectiveRaw =
        if !hasRaw then
          null
        else if lib.hasInfix "%command%" app.rawLaunchOptions then
          app.rawLaunchOptions
        else
          "%command% ${app.rawLaunchOptions}";

      # env applies the raw string's leading VAR=val assignments
      gameInvocation =
        if hasRaw then
          "env ${lib.replaceString "%command%" ''"''${game_command[@]}"'' effectiveRaw}"
        else
          ''"''${game_command[@]}"'';

      scopeProperties = {
        Description = name;
        Wants = app.systemd.target.unitName;
        After = app.systemd.target.unitName;
      }
      // app.systemd.scope.properties;

      mkPropertyArg =
        key: value:
        "--property=${key}=${if lib.isBool value then (if value then "yes" else "no") else toString value}";

      # nothing after the game here survives the wrapper being killed
      scopeStep = lib.optionalString app.systemd.enable ''
        declare -a scope=()
        if ${lib.getExe' pkgs.systemd "systemctl"} --user show --property=Version >/dev/null 2>&1; then
          scope=(
            ${lib.getExe' pkgs.systemd "systemd-run"} --user --scope --quiet
            --unit="app-steam-${app.steamRunId}-$RANDOM.scope"
            ${lib.escapeShellArgs (lib.mapAttrsToList mkPropertyArg scopeProperties)}
          )
        else
          echo "steam-config-nix: no systemd user manager, launching without a scope" >&2
          ${notify "No systemd user manager, launching ${name} without a scope"}
        fi
      '';

      scopePrefix = lib.optionalString app.systemd.enable ''"''${scope[@]}" '';

      launchStep =
        if hasOptions then
          ''
            # Steam configuration for ${name}

            ${exportAll app.env}

            declare -a wrappers=(${lib.escapeShellArgs app.wrappers})
            declare -a game_command=("$@")
            declare -a args=(${lib.escapeShellArgs app.args})

            ${app.preHook}

            ${scopeStep}
            exec ${scopePrefix}env "''${wrappers[@]}" ${gameInvocation} "''${args[@]}"
          ''
        else if hasRaw then
          "exec env ${lib.replaceString "%command%" ''"$@"'' effectiveRaw}"
        else
          ''exec "$@"'';

      package = pkgs.writeShellScriptBin "steam-app-wrapper-${toString app.id}" ''
        ${winetricksStep}
        ${launchStep}
      '';
    in
    if hasOptions || hasRaw || hasWinetricks then package else null;
in
{
  options.wrapper = lib.mkOption {
    default =
      let
        package = mkAppWrapperPackage config;
        path = if package == null then null else "${dataDir}/apps/${toString config.id}/wrapper";
        exec = if package == null then null else "${path} %command%";
      in
      {
        inherit
          package # wrapper derivation
          path # path to in-home symlink of wrapper
          exec # the string provided to steam to launch the app
          ;
      };
    visible = false;
    internal = true;
    readOnly = true;
  };
}
