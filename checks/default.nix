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
          # global default on; apps inherit unless they opt out
          desktopEntries = true;

          apps = {
            "620".launchOptionsStr = "MANGOHUD=1 %command% -vulkan";

            # opt out of the global desktop entry default
            "730" = {
              compatTool = fakeCompatTool;
              desktopEntry.enable = false;
            };

            cyberpunk = {
              id = 1091500;
              compatTool = "proton_experimental";
              betaBranch = "prerelease";
              language = "german";
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
        language = null;
        launchOptions = "/var/lib/steam-config-nix/apps/620/wrapper %command%";
      };

      "730" = {
        id = 730;
        compatTool = fakeCompatTool;
        betaBranch = null;
        language = null;
        launchOptions = null;
      };

      cyberpunk = {
        id = 1091500;
        compatTool = "proton_experimental";
        betaBranch = "prerelease";
        language = "german";
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

  desktopItems = lib.filter (
    pkg: lib.hasPrefix "steam-config-nix-" (pkg.name or "")
  ) nixosEval.config.environment.systemPackages;
  desktopItemsDir = pkgs.symlinkJoin {
    name = "desktop-items";
    paths = desktopItems;
  };
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

    # steam apps inheriting the global default: plain app id
    grep -FxR 'Exec=steam steam://rungameid/620' ${desktopItemsDir}/share/applications
    grep -FxR 'Exec=steam steam://rungameid/1091500' ${desktopItemsDir}/share/applications
    # non-steam app: 64 bit shortcut game id (id << 32 | 0x02000000)
    grep -FxR 'Exec=steam steam://rungameid/15174691026754338816' ${desktopItemsDir}/share/applications
    # app 730 opted out, so no entry is generated for it
    test ! -e ${desktopItemsDir}/share/applications/steam-config-nix-730.desktop

    touch $out
  '';
}
