{
  dataDir,
  rootOptionPath ? [ ],
}:
{ lib, pkgs, ... }:
let
  inherit (lib) types;
  inherit (import ../lib.nix lib) toSteamId3;

  usersOptionPath = rootOptionPath ++ [ "users" ];
in
{
  options = lib.setAttrByPath usersOptionPath (
    lib.mkOption {
      type = types.attrsOf (
        types.submodule (
          { name, config, ... }:
          {
            imports = [
              (import ./apps-option.nix {
                inherit dataDir;
                userId = config.id;
                supportCompatTool = false;
              })
            ];

            options = {
              id = lib.mkOption {
                type = lib.types.int;
                default = lib.strings.toIntBase10 name;
                defaultText = lib.literalExpression "lib.strings.toIntBase10 <name>";
                apply = toSteamId3;
                example = 98765432123456789;
                description = ''
                  The Steam User ID in SteamID64 or SteamID3 format.

                  User IDs can be found through through [https://steamid.io/lookup](https://steamid.io/lookup).
                '';
              };
            };

            config._module.args = { inherit pkgs; };
          }
        )
      );
      default = { };
      description = "Configuration per Steam User.";
      example = lib.literalExpression ''
        {
          # User IDs can be provided through the `id` property
          diffy = {
            id = 98765432123456789;
            apps."620".launchOptions = "-vulkan";
          };

          # Or be provided through the `<name>`
          "12345678987654321" = {
            apps."620".launchOptions = "--launcher-skip";
          };
        }'';
    }
  );
}
