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

  fakeArt = pkgs.runCommand "fake-art.jpg" { } "echo art > $out";

  noArtwork = {
    cover = null;
    header = null;
    hero = null;
    logo = null;
  };

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
            "620" = {
              id = 620;
              launchOptionsStr = "MANGOHUD=1 %command% -vulkan";
              winetricks = [ "vcrun2022" ];
            };

            # opt out of the global desktop entry default
            "730" = {
              id = 730;
              compatTool = fakeCompatTool;
              desktopEntry.enable = false;
            };

            # a disabled app is ignored entirely, even with desktopEntries on
            "999" = {
              id = 999;
              enable = false;
            };

            cyberpunk = {
              id = 1091500;
              compatTool = "proton_experimental";
              betaBranch = "prerelease";
              language = "german";
              updateBehavior = "onLaunch";
              artwork.hero = fakeArt;
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
        updateBehavior = null;
        launchOptions = "/var/lib/steam-config-nix/apps/620/wrapper %command%";
        artwork = noArtwork;
      };

      "730" = {
        id = 730;
        compatTool = fakeCompatTool;
        betaBranch = null;
        language = null;
        updateBehavior = null;
        launchOptions = null;
        artwork = noArtwork;
      };

      "999" = {
        id = 999;
        compatTool = null;
        betaBranch = null;
        language = null;
        updateBehavior = null;
        launchOptions = null;
        artwork = noArtwork;
      };

      cyberpunk = {
        id = 1091500;
        compatTool = "proton_experimental";
        betaBranch = "prerelease";
        language = "german";
        updateBehavior = "1";
        launchOptions = "/var/lib/steam-config-nix/apps/1091500/wrapper %command%";
        artwork = noArtwork // {
          hero = fakeArt;
        };
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
        artwork = noArtwork;
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

    # winetricks step runs before the launch, guarded by the prefix + a marker
    grep -F 'STEAM_COMPAT_DATA_PATH/pfx' ${strWrapper}
    grep -F 'protontricks' ${strWrapper}
    grep -F 'vcrun2022' ${strWrapper}

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
    # app 999 is disabled entirely, so it is ignored despite desktopEntries being on
    test ! -e ${desktopItemsDir}/share/applications/steam-config-nix-999.desktop

    touch $out
  '';
}
