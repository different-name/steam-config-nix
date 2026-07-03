{
  inputs,
  self,
  pkgs,
}:
let
  inherit (pkgs) lib;
  system = pkgs.stdenv.hostPlatform.system;

  fakeCompatTool = pkgs.runCommand "fake-compat-tool" { } ''
    mkdir $out
    echo '"compatibilitytools" { "compat_tools" { "Fake-Proton" { "install_path" "." } } }' > $out/compatibilitytool.vdf
  '';

  nixosEval = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      self.nixosModules.default
      {
        nixpkgs.hostPlatform = system;
        programs.steam.config = {
          enable = true;
          defaultCompatTool = "GE-Proton";

          apps = {
            "620".launchOptionsStr = "MANGOHUD=1 %command% -vulkan";

            "730".compatTool = fakeCompatTool;

            cyberpunk = {
              id = 1091500;
              compatTool = "proton_experimental";
              betaBranch = "prerelease";
              launchOptions = {
                env = {
                  WINEDLLOVERRIDES = "winmm,version=n,b";
                  TZ = null;
                };
                args = [ "--launcher-skip" ];
                wrappers = [ "gamemoderun" ];
                preHook = "echo prehook";
              };
            };
          };

          nonSteamApps = {
            vintage-story.target = "/games/vintagestory/start";
          };
        };
      }
    ];
  };

  cfg = nixosEval.config.programs.steam.config;

  actual = {
    apps = lib.mapAttrs (_: app: app.finalConfig) cfg.apps;
    nonSteamApps = lib.mapAttrs (_: app: app.finalConfig) cfg.nonSteamApps;
    extraCompatPackages = nixosEval.config.programs.steam.extraCompatPackages;
  };

  expected = {
    apps = {
      "620" = {
        id = 620;
        compatTool = null;
        betaBranch = null;
        launchOptions = "/var/lib/steam-config-nix/apps/620/wrapper %command%";
      };

      "730" = {
        id = 730;
        compatTool = fakeCompatTool;
        betaBranch = null;
        launchOptions = null;
      };

      cyberpunk = {
        id = 1091500;
        compatTool = "proton_experimental";
        betaBranch = "prerelease";
        launchOptions = "/var/lib/steam-config-nix/apps/1091500/wrapper %command%";
      };
    };

    nonSteamApps = {
      vintage-story = {
        id = 3533133079;
        compatTool = null;
        launchOptions = null;
        name = "vintage-story";
        target = "/games/vintagestory/start";
        startIn = "/games/vintagestory";
        icon = null;
        isHidden = false;
        allowOverlay = true;
        inVrLibrary = false;
      };
    };

    extraCompatPackages = [ fakeCompatTool ];
  };

  expectedJson = pkgs.writeText "expected.json" (builtins.toJSON expected);
  actualJson = pkgs.writeText "actual.json" (builtins.toJSON actual);

  strWrapper = lib.getExe cfg.apps."620".wrapper.package;
  optionsWrapper = lib.getExe cfg.apps.cyberpunk.wrapper.package;
in
{
  steam-config-patcher = self.packages.${system}.steam-config-patcher;

  nixos-module = pkgs.runCommand "nixos-module-check" { } ''
    diff ${expectedJson} ${actualJson}

    grep -Fx 'exec env MANGOHUD=1 "$@" -vulkan' ${strWrapper}

    grep -Fx 'export WINEDLLOVERRIDES="winmm,version=n,b"' ${optionsWrapper}
    grep -Fx 'unset TZ' ${optionsWrapper}
    grep -Fx 'declare -a wrappers=(gamemoderun)' ${optionsWrapper}
    grep -Fx 'declare -a args=(--launcher-skip)' ${optionsWrapper}
    grep -Fx 'echo prehook' ${optionsWrapper}

    touch $out
  '';
}
