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

  mkAppType =
    module:
    types.attrsOf (
      types.submoduleWith {
        modules = [ module ];
        specialArgs.steamConfig = config.programs.steam.config;
      }
    );
in
{
  imports = [
    (lib.mkRemovedOptionModule
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
    )

    (lib.mkChangedOptionModule
      [
        "programs"
        "steam"
        "config"
        "closeSteam"
      ]
      [
        "programs"
        "steam"
        "config"
        "onSteamRunning"
      ]
      (config: if config.programs.steam.config.closeSteam then "close" else "wait")
    )
  ];

  options.programs.steam.config = {
    enable = lib.mkEnableOption "declarative Steam configuration";

    package = lib.mkOption {
      type = types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.steam-config-patcher;
      description = "The steam-config-patcher package to use.";
    };

    onSteamRunning = lib.mkOption {
      type = types.enum [
        "wait"
        "close"
        "force-close"
        "skip"
      ];
      default = "wait";
      example = "close";
      description = ''
        What to do when configuration changes need to be written while Steam is running:

        - `"wait"`: wait for Steam to exit, then apply the changes
        - `"close"`: close Steam and apply the changes, waiting for any running games to exit first
        - `"force-close"`: close Steam and apply the changes immediately, even if a game is running
        - `"skip"`: skip writing, changes will be applied on the next activation
      '';
    };

    desktopEntries = lib.mkOption {
      type =
        types.coercedTo types.bool
          (
            enable:
            lib.warn
              "programs.steam.config.desktopEntries = ${lib.boolToString enable} is deprecated, use `desktopEntries.enable = ${lib.boolToString enable}` instead"
              { inherit enable; }
          )
          (
            types.submodule {
              options = {
                enable = lib.mkEnableOption "desktop entries for all configured apps by default";

                libraryIcons = lib.mkOption {
                  type = types.bool;
                  default = true;
                  example = false;
                  description = ''
                    Use each Steam app's own icon from your Steam library for its
                    desktop entry, instead of the generic Steam icon.

                    Icons are taken from Steam's local library cache, so an app must
                    have been seen by Steam at least once for its icon to be
                    available. They are small (typically 32x32), and fall back to
                    the Steam icon when they cannot be resolved.

                    Individual apps can opt out with
                    `desktopEntry.useLibraryIcon = false`, and setting
                    `desktopEntry.icon` explicitly always takes precedence.
                  '';
                };
              };
            }
          );
      default = { };
      example = {
        enable = true;
      };
      description = ''
        Desktop entry defaults for all configured apps.

        Setting this to a boolean is deprecated; use `desktopEntries.enable`
        instead. Individual apps can opt out with `desktopEntry.enable = false`.
      '';
    };

    notifications = lib.mkOption {
      type = types.bool;
      default = true;
      example = false;
      description = ''
        Send desktop notifications for slow launch-time steps (e.g. installing
        winetricks verbs).

        Degrades gracefully: if no notification daemon is reachable the
        notification is simply skipped.
      '';
    };

    defaultCompatTool = lib.mkOption {
      type = with types; nullOr (either str package);
      default = null;
      example = "proton_experimental";
      description = ''
        Default compatibility tool to use for Steam Play, either the internal
        name of an installed tool, or a package containing one.

        This option sets the default compatibility tool in Steam, but does not set the nix module defaults.
      '';
    };

    apps = lib.mkOption {
      type = mkAppType steamAppModule;
      default = { };
      example = lib.literalExpression ''
        {
          "Spin Rhythm XD" = {
            id = 1058830;
            launchOptionsStr = "DVXK_ASYNC=1 gamemoderun %command%";
          };
        }'';
      description = "Configuration per Steam app.";
    };

    nonSteamApps = lib.mkOption {
      type = mkAppType nonSteamAppModule;
      default = { };
      example = lib.literalExpression ''
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
        }'';
      description = "Configuration per non-Steam app.";
    };
  };

  config =
    let
      cfg = config.programs.steam.config;

      # only enabled apps are managed; disabled ones are reverted via manifest cleanup
      enabledApps = lib.filterAttrs (_: app: app.enable) cfg.apps;
      enabledNonSteamApps = lib.filterAttrs (_: app: app.enable) cfg.nonSteamApps;

      # wrapper symlinks

      allApps = (lib.attrValues enabledApps) ++ (lib.attrValues enabledNonSteamApps);
      launchOptionApps = lib.filter (app: app.wrapper.package != null) allApps;
      wrapperLinks = map (app: {
        target = app.wrapper.path;
        source = lib.getExe app.wrapper.package;
      }) launchOptionApps;

      # compat tool packages

      compatToolPackages = lib.unique (
        lib.filter lib.isDerivation ([ cfg.defaultCompatTool ] ++ map (app: app.compatTool) allApps)
      );

      compatToolDir = pkg: lib.getOutput "steamcompattool" pkg;

      # desktop entries

      desktopEntryApps = lib.filter (app: app.desktopEntry.enable) allApps;

      mkDesktopEntry = app: {
        key = "steam-config-nix-${toString app.id}";
        exec = "steam steam://rungameid/${app.steamRunId}";
        inherit (app.desktopEntry)
          name
          genericName
          comment
          icon
          categories
          ;
      };

      # patcher config

      mkCompatToolValue =
        value: if lib.isDerivation value then { path = compatToolDir value; } else value;

      mapFinalConfigs = lib.mapAttrs (
        _: value:
        value.finalConfig
        // {
          compatTool = mkCompatToolValue value.finalConfig.compatTool;
        }
      );

      patcherConfig = builtins.toJSON {
        inherit (cfg) onSteamRunning;
        defaultCompatTool = mkCompatToolValue cfg.defaultCompatTool;
        apps = mapFinalConfigs enabledApps;
        nonSteamApps = mapFinalConfigs enabledNonSteamApps;
      };

      # patcher service

      service = {
        description = "Steam config patcher script";
        restartTriggers = [ (builtins.hashString "md5" patcherConfig) ];

        config = {
          Type = "exec";
          RemainAfterExit = true; # allows service to be restarted by restartTriggers

          ExecStart = lib.escapeShellArgs [
            (lib.getExe cfg.package)
            (pkgs.writeText "steam-config-patcher-cfg" patcherConfig)
          ];
        };
      };
    in
    lib.mkIf cfg.enable (
      lib.mkMerge [
        {
          assertions =
            let
              namedApps =
                lib.mapAttrsToList (name: app: {
                  name = "apps.${name}";
                  inherit app;
                }) enabledApps
                ++ lib.mapAttrsToList (name: app: {
                  name = "nonSteamApps.${name}";
                  inherit app;
                }) enabledNonSteamApps;

              duplicateIds = lib.filterAttrs (_: entries: lib.length entries > 1) (
                builtins.groupBy (entry: toString entry.app.id) namedApps
              );

              duplicateMessages = lib.mapAttrsToList (
                id: entries: "id ${id} is used by: ${lib.concatMapStringsSep ", " (e: e.name) entries}"
              ) duplicateIds;
            in
            [
              {
                assertion = duplicateIds == { };
                message = "steam-config-nix: multiple apps configured with the same id\n${lib.concatStringsSep "\n" duplicateMessages}";
              }
            ]
            ++ map (entry: {
              assertion = !entry.app.hasLaunchOptions || entry.app.launchOptionsStr == null;
              message = "steam-config-nix: ${entry.name} sets both launchOptions and launchOptionsStr, only one may be set";
            }) namedApps
            ++ lib.mapAttrsToList (name: app: {
              assertion = app.artwork.icon == null;
              message = "steam-config-nix: apps.${name} sets artwork.icon, which is only available for non-Steam apps (Steam manages the icons of its own apps)";
            }) enabledApps;
        }

        (lib.optionalAttrs (format == "nixos") {
          programs.steam.extraCompatPackages = compatToolPackages;

          environment.systemPackages = map (
            app:
            let
              entry = mkDesktopEntry app;
            in
            pkgs.makeDesktopItem (
              {
                inherit (entry) exec categories comment;
                name = entry.key;
                desktopName = entry.name;
                type = "Application";
                terminal = false;
              }
              // lib.optionalAttrs (entry.genericName != null) { inherit (entry) genericName; }
              // lib.optionalAttrs (entry.icon != null) { icon = toString entry.icon; }
            )
          ) desktopEntryApps;

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
            ++ map (
              pkg:
              lib.nameValuePair ".local/share/Steam/compatibilitytools.d/${lib.getName pkg}" {
                source = compatToolDir pkg;
              }
            ) compatToolPackages
          );

          xdg.desktopEntries = lib.listToAttrs (
            map (
              app:
              let
                entry = mkDesktopEntry app;
              in
              lib.nameValuePair entry.key {
                inherit (entry)
                  name
                  genericName
                  comment
                  exec
                  categories
                  icon
                  ;
                type = "Application";
                terminal = false;
              }
            ) desktopEntryApps
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
