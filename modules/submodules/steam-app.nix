{
  lib,
  pkgs,
  dataDir,
}:
{ name, config, ... }:
let
  inherit (lib) types;
  baseAppModule = import ./base-app.nix { inherit lib pkgs dataDir; };

  fileOpSubmodule = types.submodule (
    { config, ... }:
    {
      options = {
        empty = lib.mkOption {
          type = types.bool;
          default = false;
          description = "Replace the file with an empty (0-byte) file.";
        };

        source = lib.mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Replace the file with contents from this store path.";
        };

        mode = lib.mkOption {
          type = types.enum [
            "replace"
            "create"
            "init"
          ];
          default = "replace";
          description = ''
            How to handle a missing target.

            - `replace` (default): only act when the target already exists; otherwise
              skip. A backup of the original is written next to the target on first
              apply.
            - `create`: create the target (and parent directories) if absent; replace
              it otherwise. No backup is written when the target did not exist.
            - `init`: like `create` but only on first apply. If the target already
              exists, leave it alone, even if its content differs from the source.
              Use this for files the application is expected to write back to (in-game
              overlay configs, save files). To push a new template, delete the target
              and re-run.
          '';
        };

        location = lib.mkOption {
          type = types.enum [
            "install"
            "prefix"
          ];
          default = "install";
          description = ''
            Root the relative target path is resolved against.

            - `install` (default): the Steam install directory
              (`steamapps/common/<dir>`).
            - `prefix`: the Proton/Wine prefix root
              (`steamapps/compatdata/<appid>/pfx`). Use this for mods that write into
              the game's user storage under `drive_c/users/steamuser/AppData/...`.
          '';
        };

        # Resolved source path passed to the patcher. Hidden so callers see the
        # `empty`/`source` pair, while the patcher only deals with a single path.
        resolvedSource = lib.mkOption {
          type = types.path;
          default =
            if config.empty then
              pkgs.runCommand "steam-app-empty-file" { } "touch $out"
            else if config.source != null then
              pkgs.runCommand "steam-config-nix-file-source" { } ''
                cp ${config.source} $out
              ''
            else
              throw "steam-config-nix: file op needs `empty = true` or a `source` path";
          visible = false;
          internal = true;
          readOnly = true;
        };
      };
    }
  );
in
{
  imports = [ baseAppModule ];

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

    files = lib.mkOption {
      type = types.attrsOf fileOpSubmodule;
      default = { };
      example = lib.literalExpression ''
        {
          # Stub a file with empty content (e.g. an unwanted intro video).
          "path/to/intro.bik".empty = true;

          # Drop a DLL alongside the game executable.
          "some-shim.dll" = {
            source = "''${pkgs.someShimPackage}/some-shim.dll";
            mode = "create";
          };

          # First-apply config that the game's overlay edits in place.
          # The template is written once; subsequent activations leave any
          # in-game tweaks alone.
          "some-config.ini" = {
            source = ./some-config.ini;
            mode = "init";
          };

          # Drop a file into the Wine prefix's user storage.
          "drive_c/users/steamuser/AppData/Local/<vendor>/<game>/mods/foo.xml" = {
            source = ./foo.xml;
            location = "prefix";
            mode = "create";
          };
        }
      '';
      description = ''
        Files to drop into the game's install directory or Proton prefix.

        Keyed by path relative to `location`'s root. Use this for asset
        replacements, intro-skip stubs, DLL injections, or first-apply config
        templates the game writes back to.

        Backups of replaced files are written once next to the target with a
        `.steam-config-nix-backup` suffix on first apply.
      '';
    };
  };

  config.finalConfig.files = lib.mapAttrsToList (relPath: op: {
    target = relPath;
    source = toString op.resolvedSource;
    inherit (op) mode location;
  }) config.files;
}
