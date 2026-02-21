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

  appModule = import ./submodules/app.nix { inherit lib pkgs dataDir; };
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
      type = types.attrsOf (types.submodule appModule);
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
        }'';
      description = "Configuration per Steam app.";
    };
  };

  config =
    let
      cfg = config.programs.steam.config;

      launchOptionApps = lib.filter (app: app.wrapper.package != null) (lib.attrValues cfg.apps);
      launchOptionLinks = map (app: {
        target = app.wrapper.path;
        source = lib.getExe app.wrapper.package;
      }) launchOptionApps;

      patcherConfig = builtins.toJSON {
        inherit (cfg) closeSteam defaultCompatTool;
        apps = lib.mapAttrs (_: app: {
          inherit (app) id compatTool;
          launchOptions = app.wrapper.exec;
        }) cfg.apps;
      };

      service = {
        description = "Steam config patcher script";
        restartTriggers = [ (lib.hashString "md5" patcherConfig) ];

        config = {
          Type = "oneshot";
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
        (lib.optionalAttrs (format == "nixos") {
          systemd.tmpfiles.rules = map (
            link: "L+ ${lib.escapeShellArg link.target} - - - - ${lib.escapeShellArg link.source}"
          ) launchOptionLinks;

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
            map (link: lib.nameValuePair link.target { inherit (link) source; }) launchOptionLinks
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
