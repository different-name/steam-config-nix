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
      hasPrefix = app.prefixPath != null;

      # points the prefix elsewhere before anything else runs, keeping the path Steam
      # chose so protontricks can be bound onto it below
      prefixStep = lib.optionalString hasPrefix ''
        scn_setup_prefix() {
          local dir parent
          dir=${lib.escapeShellArg (toString app.prefixPath)}
          parent=$(dirname "$dir")
          if [ ! -d "$parent" ]; then
            echo "steam-config-nix: prefixPath parent $parent does not exist, refusing to create it" >&2
            ${notify "prefixPath parent $parent is missing, is the drive mounted?"}
            exit 1
          fi
          mkdir -p "$dir"
          export STEAM_COMPAT_DATA_PATH="$dir"
        }
      '';

      # protontricks finds prefixes by app id under the library, so a relocated prefix is
      # bound over the one Steam made for the launch instead of being passed as a path
      protontricksCmd =
        let
          protontricks = lib.getExe' pkgs.protontricks "protontricks";
        in
        if hasPrefix then
          ''${lib.getExe' pkgs.bubblewrap "bwrap"} --dev-bind / / --bind "$STEAM_COMPAT_DATA_PATH" "$scn_compat_orig" -- ${protontricks}''
        else
          protontricks;

      # runs before the game, when Steam has set STEAM_COMPAT_* in the environment
      # marker keyed on the verb list so it only runs when the verbs change
      winetricksStep = lib.optionalString hasWinetricks ''
        scn_apply_winetricks() {
          local marker want
          if [ -z "''${STEAM_COMPAT_DATA_PATH:-}" ] || [ ! -d "$STEAM_COMPAT_DATA_PATH/pfx" ]; then
            return
          fi
          ${
            # the bind needs the path Steam picked, which only exists when Steam launched us
            lib.optionalString hasPrefix ''if [ -z "$scn_compat_orig" ]; then return; fi''
          }
          marker="$STEAM_COMPAT_DATA_PATH/steam-config-nix-winetricks"
          want=${lib.escapeShellArg (lib.concatStringsSep " " app.winetricks)}
          if [ "$(cat "$marker" 2>/dev/null)" = "$want" ]; then
            return
          fi
          echo "steam-config-nix: applying winetricks verbs: $want"
          ${notify "Installing winetricks: $want..."}
          if ${protontricksCmd} "''${STEAM_COMPAT_APP_ID}" -q ${lib.escapeShellArgs app.winetricks}; then
            printf '%s' "$want" > "$marker"
            ${notify "winetricks installed: $want"}
          else
            echo "steam-config-nix: winetricks failed, continuing to launch" >&2
            ${notify "winetricks failed for app ${toString app.id}"}
          fi
        }
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

      launch =
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

      # the steps with working variables of their own are functions, so those stay out
      # of the launch scope and away from preHook
      calls = lib.concatStringsSep "\n" (
        lib.optional hasPrefix "scn_setup_prefix" ++ lib.optional hasWinetricks "scn_apply_winetricks"
      );

      sections = lib.filter (section: section != "") [
        # only the winetricks bind needs the path steam picked
        (lib.optionalString (
          hasPrefix && hasWinetricks
        ) ''scn_compat_orig="''${STEAM_COMPAT_DATA_PATH:-}"'')
        prefixStep
        winetricksStep
        calls
        launch
      ];

      package = pkgs.writeShellScriptBin "steam-app-wrapper-${toString app.id}" (
        lib.concatStringsSep "\n" sections
      );
    in
    if hasOptions || hasRaw || hasWinetricks || hasPrefix then package else null;
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
