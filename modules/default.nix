self: format:
{ lib, config, ... }:
let
  cfg = config.programs.steam.config;
  cfgJson = builtins.toJSON cfg;

  dataHome =
    assert builtins.isString format;
    if format == "nixos" then
      "/var/lib"
    else if format == "home-manager" then
      config.xdg.dataHome
    else
      throw "unexpected format, must be one of: nixos, home-manager";

  dataDir = "${dataHome}/steam-config-nix";

  # user configs (programs.steam.config.users) + global launch option configs
  finalUsersConfig = lib.attrValues (
    {
      shared = {
        id = "shared";
        apps = lib.mapAttrs (_: app: {
          inherit (app) id launchOptions wrapperPath;
        }) cfg.apps;
      };
    }
    // cfg.users
  );

  launchOptionLinks = lib.concatMap (
    user:
    lib.concatMap (
      app:
      lib.optional (app.launchOptions != null) {
        target = lib.removePrefix "${dataHome}/" app.wrapperPath;
        source = lib.getExe app.launchOptions;
      }
    ) (lib.attrValues user.apps)
  ) finalUsersConfig;

  description = "Steam config patcher script";
  restartTriggers = [ cfgJson ];

  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true; # allows service to be restarted by restartTriggers
    ExecStart = lib.escapeShellArgs [
      (lib.getExe cfg.package)
      cfgJson
    ];
  };
in
{
  imports = [ (import ./submodules/root-options.nix { inherit self dataDir; }) ];

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.optionalAttrs (format == "nixos") {
        systemd.tmpfiles.rules = map (
          { target, source }: "L+ /var/lib/${lib.escapeShellArg target} - - - - ${lib.escapeShellArg source}"
        ) launchOptionLinks;

        # we use a system service instead of a user service due to https://github.com/NixOS/nixpkgs/issues/246611
        # nixos user services also don't restart on rebuild, requiring a user activation script
        systemd.services."steam-config-patcher@" = {
          inherit description restartTriggers;

          serviceConfig = serviceConfig // {
            User = "%i";
            Group = "users";
          };
        };

        systemd.targets.multi-user.wants =
          let
            normalUsers = lib.filter (user: user.isNormalUser) (lib.attrValues (config.users.users));
          in
          map (user: "steam-config-patcher@${user.name}.service") normalUsers;
      })

      (lib.optionalAttrs (format == "home-manager") {
        xdg.dataFile = lib.listToAttrs (
          map (
            { target, source }:
            {
              name = lib.removePrefix dataHome target;
              value = { inherit source; };
            }
          ) launchOptionLinks
        );

        systemd.user.services."steam-config-patcher" = {
          Unit = {
            Description = description;
            X-Restart-Triggers = restartTriggers;
          };

          Service = serviceConfig;
          Install.WantedBy = [ "default.target" ];
        };
      })
    ]
  );
}
