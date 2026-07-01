self: format:
{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib) types;

  dataHome =
    if format == "nixos" then
      "/var/lib"
    else if format == "home-manager" then
      config.xdg.dataHome
    else
      throw "unexpected `format`, must be one of: nixos, home-manager";
  dataDir = "${dataHome}/steam-config-nix";

  steamAppModule = import ./submodules/steam-app.nix { inherit lib pkgs dataDir; };
  nonSteamAppModule = import ./submodules/non-steam-app.nix { inherit lib pkgs dataDir; };
in
{
  imports = lib.singleton (
    lib.mkRemovedOptionModule
      [
        "programs"
        "steam"
        "config"
        "users"
      ]
      ''
        Please use global app configuration instead.
        See https://github.com/different-name/steam-config-nix/discussions/33
      ''
  );

  options.programs.steam.config = {
    enable = lib.mkEnableOption "declarative Steam configuration";

    package = lib.mkOption {
      type = types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.steam-config-patcher;
      description = "The steam-config-patcher package to use.";
    };

    closeSteam = lib.mkEnableOption "automatic Steam shutdown before writing configuration changes";

    defaultCompatTool = lib.mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "proton_experimental";
      description = ''
        Default compatibility tool to use for Steam Play.

        This option sets the default compatibility tool in Steam, but does not set the nix module defaults.
      '';
    };

    apps = lib.mkOption {
      type = types.attrsOf (types.submodule steamAppModule);
      default = { };
      example = lib.literalExpression ''
        {
          # App IDs can be provided through the `id` property
          spin-rhythm = {
            id = 1058830;
            launchOptionsStr = "DVXK_ASYNC=1 gamemoderun %command%";
          };

          # Or be provided through the `<name>`
          "620".launchOptionsStr = "-vulkan";
        }'';
      description = "Configuration per Steam app.";
    };

    nonSteamApps = lib.mkOption {
      type = types.attrsOf (types.submodule nonSteamAppModule);
      default = { };
      example = lib.literalExpression ''
        {
          # App IDs can be provided through the `id` property
          spin-rhythm = {
            id = 1058830;
            launchOptionsStr = "DVXK_ASYNC=1 gamemoderun %command%";
          };

          # Or be provided through the `<name>`
          "620".launchOptionsStr = "-vulkan";
        }'';
      description = "Configuration per Steam app.";
    };

    winetricks = lib.mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          winePrefix = lib.mkOption {
            type = types.str;
            example = "/home/user/.wine";
            description = "Path to the Wine prefix (WINEPREFIX).";
          };

          verbs = lib.mkOption {
            type = types.listOf types.str;
            default = [ ];
            example = lib.literalExpression ''
              [ "vcrun2022" "corefonts" "dxvk" ]
            '';
            description = "List of winetricks verbs to install in this prefix.";
          };
        };
      });
      default = { };
      example = lib.literalExpression ''
        {
          "my-app" = {
            winePrefix = "/home/user/.local/share/wineprefixes/myapp";
            verbs = [ "vcrun2022" "corefonts" ];
          };
        }'';
      description = ''
        Declarative winetricks package installations for arbitrary Wine prefixes.

        Each entry specifies a path to a Wine prefix and a list of winetricks verbs
        to install in that prefix.

        For per-game winetricks configuration tied to a Steam app, use the
        `apps.<name>.winetricks` option instead, which auto-detects the prefix path.
      '';
    };
  };

  config =
    let
      cfg = config.programs.steam.config;

      # wrapper symlinks

      allApps =
        (lib.filter (app: app.enable) (lib.attrValues cfg.apps))
        ++ (lib.filter (app: app.enable) (lib.attrValues cfg.nonSteamApps));

      launchOptionApps = lib.filter (app: app.wrapper.package != null) allApps;
      wrapperLinks = map (app: {
        target = app.wrapper.path;
        source = lib.getExe app.wrapper.package;
      }) launchOptionApps;

      # patcher config

      mapFinalConfigs =
        attrs: lib.mapAttrs (_: value: value.finalConfig) (lib.filterAttrs (_: value: value.enable) attrs);

      patcherConfig = builtins.toJSON {
        inherit (cfg) closeSteam defaultCompatTool;
        apps = mapFinalConfigs cfg.apps;
        nonSteamApps = mapFinalConfigs cfg.nonSteamApps;
      };

      # winetricks

      winetricksApps = lib.filter (
        app: app.winetricks != null && app.winetricks.verbs != [ ]
      ) allApps;

      hasWinetricksTasks = winetricksApps != [ ] || cfg.winetricks != { };

      winetricksScript = pkgs.writeShellScriptBin "steam-winetricks" ''
        set -u
        export PATH="${lib.makeBinPath [ pkgs.winetricks ]}:$PATH"

        run_winetricks() {
          local prefix="$1"
          shift
          if [ ! -d "$prefix" ]; then
            echo "steam-config-nix: warning: WINEPREFIX '$prefix' does not exist, skipping winetricks"
            return 0
          fi
          echo "steam-config-nix: installing winetricks verbs in '$prefix': $*"
          WINEPREFIX="$prefix" winetricks -q "$@" || echo "steam-config-nix: warning: winetricks failed for '$prefix'"
        }

        ${lib.concatStringsSep "\n" (map (app:
          let
            prefix = if app.winetricks.winePrefix != null then app.winetricks.winePrefix else "\"$HOME/.steam/steam/steamapps/compatdata/${toString app.id}/pfx\"";
            verbs = lib.escapeShellArgs app.winetricks.verbs;
          in
          "run_winetricks ${prefix} ${verbs}"
        ) winetricksApps)}

        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (_: wt:
          "run_winetricks \"${wt.winePrefix}\" ${lib.escapeShellArgs wt.verbs}"
        ) cfg.winetricks)}
      '';

      winetricksConfigHash = builtins.hashString "md5" (builtins.toJSON {
        inherit (cfg) winetricks;
        appWinetricks = map (app: app.winetricks) winetricksApps;
      });

      # patcher service

      service = {
        description = "Steam config patcher script";
        restartTriggers = [
          (builtins.hashString "md5" patcherConfig)
        ] ++ lib.optional hasWinetricksTasks winetricksConfigHash;

        config = {
          Type = "oneshot";
          RemainAfterExit = true; # allows service to be restarted by restartTriggers

          ExecStart = lib.escapeShellArgs [
            (lib.getExe cfg.package)
            (pkgs.writeText "steam-config-patcher-cfg" patcherConfig)
          ];
        } // lib.optionalAttrs hasWinetricksTasks {
          ExecStartPost = "${lib.getExe winetricksScript}";
        };
      };
    in
    lib.mkIf cfg.enable (
      lib.mkMerge [
        (lib.optionalAttrs (format == "nixos") {
          systemd.tmpfiles.rules = map (
            link: "L+ ${lib.escapeShellArg link.target} - - - - ${lib.escapeShellArg link.source}"
          ) wrapperLinks;

          # system service instead of a user service due to https://github.com/NixOS/nixpkgs/issues/246611
          # nixos user services also don't restart on rebuild, requiring a user activation script
          systemd.services."steam-config-patcher@" = {
            inherit (service) description restartTriggers;

            serviceConfig = service.config // {
              User = "%i";
              Group = "users";
            };
          };

          systemd.targets.multi-user.wants =
            let
              normalUsers = lib.filter (user: user.isNormalUser) (lib.attrValues config.users.users);
            in
            map (user: "steam-config-patcher@${user.name}.service") normalUsers;
        })

        (lib.optionalAttrs (format == "home-manager") {
          home.file = lib.listToAttrs (
            map (link: lib.nameValuePair link.target { inherit (link) source; }) wrapperLinks
          );

          systemd.user.services."steam-config-patcher" = {
            Unit = {
              Description = service.description;
              X-Restart-Triggers = service.restartTriggers;
            };

            Service = service.config;
            Install.WantedBy = [ "default.target" ];
          };
        })
      ]
    );
}
