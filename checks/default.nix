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

  # fixtures + input for the patcher integration check
  seedConfigVdf = pkgs.writeText "config.vdf" ''
    "InstallConfigStore"
    {
    	"Software" { "Valve" { "Steam" { "CompatToolMapping" { } } } }
    }
  '';
  seedLocalconfigVdf = pkgs.writeText "localconfig.vdf" ''
    "UserLocalConfigStore"
    {
    	"Software" { "Valve" { "Steam" { "Apps" { } } } }
    }
  '';
  seedAppmanifest = pkgs.writeText "appmanifest_620.acf" ''
    "AppState"
    {
    	"appid"		"620"
    	"installdir"		"Test Game"
    	"UserConfig" { "language" "english" }
    }
  '';
  seedModFile = pkgs.writeText "mod.txt" "modcontent";
  patcherInput = pkgs.writeText "patcher-input.json" (
    builtins.toJSON {
      onSteamRunning = "wait";
      defaultCompatTool = null;
      apps."Test Game" = {
        id = 620;
        compatTool = "GE-Proton";
        launchOptions = "test-launch-wrapper %command%";
        betaBranch = "beta";
        language = "german";
        updateBehavior = "1";
        artwork = {
          cover = null;
          header = null;
          hero = null;
          logo = null;
        };
        files = [
          {
            location = "install";
            target = "mods/test.txt";
            source = "${seedModFile}";
            overwriteChanges = true;
            executable = null;
          }
        ];
        removeFiles = [
          {
            location = "install";
            target = "unwanted.txt";
          }
        ];
      };
      nonSteamApps = { };
    }
  );

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
          desktopEntries.enable = true;

          apps = {
            "620" = {
              id = 620;
              launchOptionsStr = "MANGOHUD=1 %command% -vulkan";
              winetricks = [ "vcrun2022" ];
              # an explicit icon always wins over the library-icon default
              desktopEntry.icon = "custom-icon";
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
              files.install."mods/test.pak".source = fakeArt;
              removeFiles.install = [ "movies/intro.bik" ];
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
        libraryIcon = false;
        launchOptions = "/var/lib/steam-config-nix/apps/620/wrapper %command%";
        artwork = noArtwork;
        files = [ ];
        removeFiles = [ ];
      };

      "730" = {
        id = 730;
        compatTool = fakeCompatTool;
        betaBranch = null;
        language = null;
        updateBehavior = null;
        libraryIcon = false;
        launchOptions = null;
        artwork = noArtwork;
        files = [ ];
        removeFiles = [ ];
      };

      "999" = {
        id = 999;
        compatTool = null;
        betaBranch = null;
        language = null;
        updateBehavior = null;
        # disabled app: finalConfig still computed but filtered out before use
        libraryIcon = true;
        launchOptions = null;
        artwork = noArtwork;
        files = [ ];
        removeFiles = [ ];
      };

      cyberpunk = {
        id = 1091500;
        compatTool = "proton_experimental";
        betaBranch = "prerelease";
        language = "german";
        updateBehavior = "1";
        libraryIcon = true; # inherits the global default (on)
        launchOptions = "/var/lib/steam-config-nix/apps/1091500/wrapper %command%";
        artwork = noArtwork // {
          hero = fakeArt;
        };
        files = [
          {
            location = "install";
            target = "mods/test.pak";
            source = "${fakeArt}";
            overwriteChanges = true;
            executable = null;
          }
        ];
        removeFiles = [
          {
            location = "install";
            target = "movies/intro.bik";
          }
        ];
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

  failingAssertions =
    appConfig:
    let
      eval = lib.evalModules {
        specialArgs = { inherit pkgs; };
        modules = [
          { config._module.check = false; }
          {
            options.assertions = lib.mkOption {
              type = lib.types.listOf lib.types.unspecified;
              default = [ ];
            };
            options.warnings = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
            };
          }
          self.homeModules.default
          {
            programs.steam.config = {
              enable = true;
              apps."bad" = { id = 111; } // appConfig;
            };
          }
        ];
      };
    in
    map (a: a.message) (lib.filter (a: !a.assertion) eval.config.assertions);

  hasFailure = substr: assertions: lib.any (lib.hasInfix substr) assertions;

  assertionsOk =
    lib.assertMsg (
      hasFailure "exactly one of" (failingAssertions {
        files.install."x" = {
          source = fakeArt;
          text = "hi";
        };
      })
    ) "setting both source and text should fail"
    && lib.assertMsg (hasFailure "exactly one of" (failingAssertions { files.install."x" = { }; }))
      "setting neither source nor text should fail"
    && lib.assertMsg (hasFailure "unsafe target" (failingAssertions { files.install."../escape".source = fakeArt; }))
      "an unsafe file target should fail"
    && lib.assertMsg (hasFailure "unsafe path" (failingAssertions { removeFiles.install = [ "../escape" ]; }))
      "an unsafe removeFiles path should fail"
    && lib.assertMsg (hasFailure "same target" (failingAssertions {
      files.install = {
        "a".target = "shared.dll";
        "b".target = "shared.dll";
      };
      files.install."a".source = fakeArt;
      files.install."b".source = fakeArt;
    })) "duplicate resolved targets should fail"
    && lib.assertMsg (failingAssertions {
      files.install."mods/ok.pak".source = fakeArt;
      removeFiles.install = [ "movies/intro.bik" ];
    } == [ ]) "a valid file config should not fail";
in
{
  steam-config-patcher = self.packages.${system}.steam-config-patcher;

  # runs the real patcher binary against a seeded Steam tree (via HOME),
  # exercising get_steam_dir discovery and on-disk vdf patching end to end
  patcher-integration =
    pkgs.runCommand "patcher-integration"
      { nativeBuildInputs = [ self.packages.${system}.steam-config-patcher ]; }
      ''
        export HOME="$PWD/home"
        steam="$HOME/.local/share/Steam"
        install="$steam/steamapps/common/Test Game"
        mkdir -p "$steam/config" "$steam/userdata/111/config" "$steam/steamapps" "$install"
        cp ${seedConfigVdf} "$steam/config/config.vdf"
        cp ${seedLocalconfigVdf} "$steam/userdata/111/config/localconfig.vdf"
        cp ${seedAppmanifest} "$steam/steamapps/appmanifest_620.acf"
        echo unwanted > "$install/unwanted.txt"

        steam-config-patcher ${patcherInput}

        acf="$steam/steamapps/appmanifest_620.acf"
        lc="$steam/userdata/111/config/localconfig.vdf"

        grep -q GE-Proton "$steam/config/config.vdf"
        grep -q test-launch-wrapper "$lc"
        grep -q '"BetaKey"' "$acf"
        grep -q beta "$acf"
        grep -q german "$acf"
        grep -q AutoUpdateBehavior "$acf"
        test -f "$steam/userdata/111/config/steam-config-nix-manifest.json"

        # file operations: dropped file placed, removed file gone, manifest written
        grep -q modcontent "$install/mods/test.txt"
        test ! -e "$install/unwanted.txt"
        test -f "$steam/config/steam-config-nix-files.json"

        # idempotent second run must still succeed
        steam-config-patcher ${patcherInput}

        grep -q modcontent "$install/mods/test.txt"

        touch $out
      '';

  module-assertions = pkgs.runCommand "module-assertions-check" { } (
    assert assertionsOk;
    "touch $out"
  );

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
    # library icons are the default, so the entry uses the managed icon name
    grep -FxR 'Icon=steam-config-nix-1091500' ${desktopItemsDir}/share/applications
    # an explicit desktopEntry.icon wins over the library-icon default
    grep -FxR 'Icon=custom-icon' ${desktopItemsDir}/share/applications/steam-config-nix-620.desktop
    # non-steam app: 64 bit shortcut game id (id << 32 | 0x02000000)
    grep -FxR 'Exec=steam steam://rungameid/15174691026754338816' ${desktopItemsDir}/share/applications
    # app 730 opted out, so no entry is generated for it
    test ! -e ${desktopItemsDir}/share/applications/steam-config-nix-730.desktop
    # app 999 is disabled entirely, so it is ignored despite desktopEntries being on
    test ! -e ${desktopItemsDir}/share/applications/steam-config-nix-999.desktop

    touch $out
  '';
}
