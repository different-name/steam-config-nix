self:
{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib) types;
  nestedAttrsOfStrings = types.lazyAttrsOf (types.either types.str nestedAttrsOfStrings);

  # modified from home-manager lib.shell.exportAll
  # https://github.com/nix-community/home-manager/blob/89c9508bbe9b40d36b3dc206c2483ef176f15173/modules/lib/shell.nix#L36-L42
  exportUnset = n: v: if v == null then "unset ${n}" else ''export ${n}="${toString v}"'';
  exportAll = lib.concatMapAttrsStringSep "\n" exportUnset;

  cfg = config.programs.steam.config;

  dataDir = "${config.xdg.dataHome}/steam-config-nix";

  # get a SteamID3 from a SteamID64
  # https://gist.github.com/bcahue/4eae86ae1d10364bb66d
  toSteamId3 =
    userId:
    let
      steamId64Ident = 76561197960265728;
      isSteam64 = userId >= steamId64Ident;
    in
    if isSteam64 then toString (userId - steamId64Ident) else userId;

  writeWrapperBin = appId: text: pkgs.writeShellScriptBin "steam-app-wrapper-${toString appId}" text;

  writeLaunchOptionsStrBin =
    appId: launchOptions:
    let
      launchCommand =
        if lib.strings.hasInfix "%command%" launchOptions then
          lib.replaceString "%command%" ''"$@"'' launchOptions
        else
          ''"$@" ${launchOptions}'';
    in
    writeWrapperBin appId "exec env ${launchCommand}";

  writeLaunchOptionsSetBin =
    appId: launchOptionsSet:
    let
      prefix = lib.escapeShellArgs launchOptionsSet.wrappers;
      suffix = lib.escapeShellArgs launchOptionsSet.args;
    in
    writeWrapperBin appId ''
      ${exportAll launchOptionsSet.env}
      ${launchOptionsSet.extraConfig}
      exec env ${prefix} "$@" ${suffix}
    '';

  launchOptionsSubmodule = types.submodule {
    options = {
      env = lib.mkOption {
        type =
          with types;
          lazyAttrsOf (
            nullOr (oneOf [
              str
              path
              int
              float
              bool
            ])
          );
        default = { };
        example = lib.literalExpression ''
          {
            WINEDLLOVERRIDES = "winmm,version=n,b";
            "TZ" = null;
          }
        '';
        description = ''
          Environment variables to export in the launch script.
          You can also unset variables by setting their value to `null`.
        '';
      };
      wrappers = lib.mkOption {
        type = types.listOf (types.coercedTo types.package lib.getExe types.str);
        default = [ ];
        example = lib.literalExpression ''
          [
              (lib.getExe' pkgs.mangohud "mangohud")

              pkgs.myWrapperProgram

              # Need to enable gamemode module in NixOS
              "gamemoderun"
            ]
        '';
        description = "Executables to wrap the game with.";
      };
      args = lib.mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = lib.literalExpression ''
          ["-modded" "--launcher-skip" "-skipStartScreen"]
        '';
        description = "CLI arguments to pass to the game.";
      };
      extraConfig = lib.mkOption {
        type = types.lines;
        default = "";
        example = ''
          if [[ "$*" != *"--no-vr"* ]]; then
            export PROTON_ENABLE_WAYLAND=1
          fi
        '';
        description = "Additional bash code to execute before the game.";
      };
    };
  };

  mkSteamAppsOption =
    userId:
    {
      supportCompatTool ? false,
    }:
    lib.mkOption {
      type = types.attrsOf (
        types.submodule (
          { config, name, ... }:
          {
            options = {
              id = lib.mkOption {
                type = types.int;
                default = lib.strings.toIntBase10 name;
                defaultText = lib.literalExpression "lib.strings.toIntBase10 <name>";
                example = 438100;
                description = ''
                  The Steam App ID.

                  App IDs can be found through the game's store page URL.

                  If an ID is not provided, the app's `<name>` will be used.
                '';
              };

              launchOptions = lib.mkOption {
                type =
                  with types;
                  nullOr (oneOf [
                    package
                    launchOptionsSubmodule
                    (coercedTo singleLineStr (writeLaunchOptionsStrBin config.id) package)
                  ]);
                default = null;
                description = ''
                  The Launch options to use.

                  Launch options can be provided as:

                  **`singleLineStr`**

                  ```nix
                  '''env -u TZ PRESSURE_VESSEL_FILESYSTEMS_RW="$XDG_RUNTIME_DIR/wivrn/comp_ipc" %command% --use-d3d11'''
                  ```

                  **`package`**

                  ```nix
                  pkgs.writeShellScriptBin "vrchat-wrapper" '''
                    export PRESSURE_VESSEL_FILESYSTEMS_RW="$XDG_RUNTIME_DIR/wivrn/comp_ipc"
                    unset TZ

                    if [[ "$*" == *"-force-vulkan"* ]]; then
                      export PROTON_ENABLE_WAYLAND=1
                    fi

                    exec ''${lib.getExe pkgs.gamemode} "${"''\${args[@]}"}" --use-d3d11
                  ''';
                  ```

                  **`launchOptionsSubmodule`**

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
                    extraConfig = '''
                      if [[ "$*" == *"-force-vulkan"* ]]; then
                        export PROTON_ENABLE_WAYLAND=1
                      fi
                    ''';
                  };
                  ```'';
                example = lib.literalExpression ''
                  {
                    env.WINEDLLOVERRIDES = "winmm,version=n,b";
                    args = [
                      "--launcher-skip"
                      "-skipStartScreen"
                    ];
                  };'';
                apply =
                  value:
                  if (lib.isDerivation value) || value == null then
                    value
                  else
                    writeLaunchOptionsSetBin config.id value;
              };

              wrapperPath = lib.mkOption {
                type = types.nullOr types.path;
                default =
                  if config.launchOptions != null then
                    "${dataDir}/users/${toString userId}/app-wrappers/${toString config.id}"
                  else
                    null;
                defaultText = lib.literalExpression "\${config.xdg.dataHome}/steam-config-nix/users/<user-id>/app-wrappers/<app-id>";
                example = "/home/diffy/1361210-wrapper";
                description = "A stable path outside of the nix store to link the app wrapper script.";
              };
            }
            // (lib.optionalAttrs supportCompatTool {
              compatTool = lib.mkOption {
                type = types.nullOr types.str;
                default = null;
                example = "proton_experimental";
                description = "Compatibility tool to use.";
              };
            });
          }
        )
      );

      default = { };
      example = lib.literalExpression ''
        {
          # App IDs can be provided through the `id` property
          spin-rhythm = {
            id = 1058830;
            launchOptions = "DVXK_ASYNC=1 gamemoderun %command%";
          };

          # Or be provided through the `<name>`
          "620".launchOptions = "-vulkan";
        };'';
      description = "Configuration per Steam app.";
    };

  # from home-manager's firefox module
  # https://github.com/nix-community/home-manager/blob/e82585308aef3d4cc2c36c7b6946051c8cdf24ef/modules/programs/firefox/mkFirefoxModule.nix#L151-L175
  mkNoDuplicateAssertion =
    entities: entityKind:
    (
      let
        findDuplicateIds =
          entities: lib.filterAttrs (_: entityNames: lib.length entityNames != 1) (lib.zipAttrs entities);

        duplicates = findDuplicateIds (
          lib.mapAttrsToList (entityName: entity: { "${toString entity.id}" = entityName; }) entities
        );

        mkMsg =
          entityId: entityNames: "  - ID ${entityId} is used by " + lib.concatStringsSep ", " entityNames;
      in
      {
        assertion = duplicates == { };
        message = ''
          Must not have a Steam ${entityKind} with an existing ID but
        ''
        + lib.concatMapAttrsStringSep "\n" mkMsg duplicates;
      }
    );
in
{
  imports = [
    (lib.mkRemovedOptionModule [ "programs" "steam" "localconfig" ] ''
      programs.steam.localconfig has been removed in favor of programs.steam.config
      See the steam-config-nix readme for new usage instructions
    '')

    {
      assertions = [
        (mkNoDuplicateAssertion cfg.users "user")
      ]
      ++ (lib.concatMap (user: user.assertions) (lib.attrValues cfg.users));
    }
  ];

  options.programs.steam.config = {
    enable = lib.mkEnableOption "declarative Steam configuration";

    package = lib.mkOption {
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.steam-config-patcher;
      description = "The steam-config-patcher package to use.";
      type = types.package;
    };

    steamDir = lib.mkOption {
      type = types.path;
      default = "${config.home.homeDirectory}/.steam/steam";
      defaultText = lib.literalExpression "\${config.home.homeDirectory}/.steam/steam";
      description = "Path to the Steam directory.";
      example = "/home/diffy/.local/share/Steam";
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

    apps = mkSteamAppsOption "shared" { supportCompatTool = true; };

    users = lib.mkOption {
      type = types.attrsOf (
        types.submodule (
          { config, name, ... }:
          {
            imports = [
              (pkgs.path + "/nixos/modules/misc/assertions.nix")
            ];

            options = {
              id = lib.mkOption {
                type = types.int;
                default = lib.strings.toIntBase10 name;
                defaultText = lib.literalExpression "lib.strings.toIntBase10 <name>";
                apply = toSteamId3;
                example = 98765432123456789;
                description = ''
                  The Steam User ID in SteamID64 or SteamID3 format.

                  User IDs can be found through through [https://steamid.io/lookup](https://steamid.io/lookup).
                '';
              };

              apps = mkSteamAppsOption config.id { };
            };

            config.assertions = [
              (mkNoDuplicateAssertion config.apps "app")
            ];
          }
        )
      );
      default = { };
      description = "Configuration per Steam User.";
      example = {
        # User IDs can be provided through the `id` property
        diffy = {
          id = 98765432123456789;
          apps."620".launchOptions = "-vulkan";
        };

        # Or be provided through the `<name>`
        "12345678987654321" = {
          apps."620".launchOptions = "--launcher-skip";
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    home.file =
      let
        userAppConfigs = cfg.users // {
          shared = {
            id = "shared";
            apps = lib.mapAttrs (_: app: {
              inherit (app) id launchOptions wrapperPath;
            }) cfg.apps;
          };
        };
      in
      lib.listToAttrs (
        lib.flatten (
          lib.mapAttrsToList (
            _: user:
            lib.mapAttrsToList (_: app: {
              name = app.wrapperPath;
              value.source = lib.getExe app.launchOptions;
            }) (lib.filterAttrs (_: app: app.launchOptions != null) user.apps)
          ) userAppConfigs
        )
      );

    home.activation.steam-config-patcher = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${lib.getExe cfg.package} ${lib.escapeShellArg (builtins.toJSON cfg)}
    '';
  };
}
