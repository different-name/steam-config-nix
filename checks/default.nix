{ inputs, self, ... }:
{
  perSystem =
    {
      pkgs,
      system,
      self',
      ...
    }:
    let
      inherit (pkgs) lib;

      fakeCompatTool = pkgs.runCommand "fake-compat-tool" { } ''
        mkdir $out
        echo '"compatibilitytools" { "compat_tools" { "Fake-Proton" { "install_path" "." } } }' > $out/compatibilitytool.vdf
      '';

      # proton-cachyos ships the vdf under bin/ with no steamcompattool output
      fakeBinCompatTool = pkgs.runCommand "fake-bin-compat-tool" { } ''
        mkdir -p $out/bin
        echo '"compatibilitytools" { "compat_tools" { "Bin-Proton" { "install_path" "." } } }' > $out/bin/compatibilitytool.vdf
      '';

      fakeArt = pkgs.runCommand "fake-art.jpg" { } "echo art > $out";

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
      patcherInput = import ./patcher-input.nix { inherit pkgs seedModFile; };

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
            system.stateVersion = "26.05";
            nixpkgs.hostPlatform = system;
            programs.steam.config = {
              enable = true;
              defaultCompatTool = "GE-Proton";
              desktopEntries.enable = true;

              apps = {
                "620" = {
                  rawLaunchOptions = "MANGOHUD=1 %command% -vulkan";
                  winetricks = [ "vcrun2022" ];
                  prefixPath = "/mnt/prefixes/620";
                  desktopEntry.icon = "custom-icon";
                };

                "440" = {
                  rawLaunchOptions = "-windowed -novid";
                };

                "730" = {
                  compatTool = fakeCompatTool;
                  desktopEntry.enable = false;
                };

                "999" = {
                  enable = false;
                };

                "1091500" = {
                  name = "cyberpunk";
                  compatTool = "proton_experimental";
                  betaBranch = "prerelease";
                  language = "german";
                  updateBehavior = "onLaunch";
                  allowDownloadsWhileRunning = "always";
                  artwork.hero = fakeArt;
                  files.game.place."mods/test.pak".source = fakeArt;
                  files.game.remove = [ "movies/intro.bik" ];
                  files.game.patch."config/user.ini" = {
                    format = "ini";
                    content.Video.Fullscreen = 1;
                  };
                  env.TZ = null;
                  dllOverrides = {
                    winmm = "n,b";
                    version = "n,b";
                  };
                  args = [ "--launcher-skip" ];
                  wrappers = [ "gamemoderun" ];
                  preHook = "echo prehook";
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

      expected = import ./expected.nix { inherit fakeCompatTool fakeArt noArtwork; };

      expectedJson = pkgs.writeText "expected.json" (builtins.toJSON expected);
      actualJson = pkgs.writeText "actual.json" (builtins.toJSON actual);

      strWrapper = lib.getExe cfg.apps."620".wrapper.package;
      rawArgsWrapper = lib.getExe cfg.apps."440".wrapper.package;
      optionsWrapper = lib.getExe cfg.apps."1091500".wrapper.package;

      desktopItems = lib.filter (
        pkg: lib.hasPrefix "steam-config-nix-" (pkg.name or "")
      ) nixosEval.config.environment.systemPackages;
      desktopItemsDir = pkgs.symlinkJoin {
        name = "desktop-items";
        paths = desktopItems;
      };

      evalApp =
        appConfig:
        lib.evalModules {
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
                apps."111" = {
                  name = "bad";
                }
                // appConfig;
              };
            }
          ];
        };

      failingAssertions =
        appConfig:
        let
          eval = evalApp appConfig;
        in
        map (a: a.message) (lib.filter (a: !a.assertion) eval.config.assertions);

      appWarnings = appConfig: (evalApp appConfig).config.warnings;

      resolvedPrefixPath =
        appConfig: (evalApp appConfig).config.programs.steam.config.apps."111".prefixPath;

      hasFailure = substr: assertions: lib.any (lib.hasInfix substr) assertions;

      assertionsOk =
        lib.assertMsg (
          resolvedPrefixPath { env.STEAM_COMPAT_DATA_PATH = "/mnt/games/pfx"; } == "/mnt/games/pfx"
        ) "prefixPath should default to env.STEAM_COMPAT_DATA_PATH"
        && lib.assertMsg (
          resolvedPrefixPath {
            env.STEAM_COMPAT_DATA_PATH = "/from/env";
            prefixPath = "/explicit";
          } == "/explicit"
        ) "an explicit prefixPath should win over env.STEAM_COMPAT_DATA_PATH"
        && lib.assertMsg (
          resolvedPrefixPath { env.STEAM_COMPAT_DATA_PATH = null; } == null
        ) "a non path env.STEAM_COMPAT_DATA_PATH should leave prefixPath unset"
        && lib.assertMsg (hasFailure "STEAM_COMPAT_DATA_PATH in rawLaunchOptions" (appWarnings {
          rawLaunchOptions = "STEAM_COMPAT_DATA_PATH=/blah %command%";
        })) "STEAM_COMPAT_DATA_PATH in rawLaunchOptions should warn"
        && lib.assertMsg (hasFailure "WINEDLLOVERRIDES in rawLaunchOptions" (appWarnings {
          rawLaunchOptions = "WINEDLLOVERRIDES=d3d11=n %command%";
        })) "WINEDLLOVERRIDES in rawLaunchOptions should warn"
        && lib.assertMsg (
          appWarnings { rawLaunchOptions = "gamemoderun %command%"; } == [ ]
        ) "an ordinary rawLaunchOptions string should not warn"
        && lib.assertMsg (hasFailure "exactly one of" (failingAssertions {
          files.game.place."x" = {
            source = fakeArt;
            text = "hi";
          };
        })) "setting both source and text should fail"
        && lib.assertMsg (hasFailure "exactly one of" (failingAssertions {
          files.game.place."x" = { };
        })) "setting neither source nor text should fail"
        && lib.assertMsg (hasFailure "unsafe target" (failingAssertions {
          files.game.place."../escape".source = fakeArt;
        })) "an unsafe file target should fail"
        && lib.assertMsg (hasFailure "unsafe path" (failingAssertions {
          files.game.remove = [ "../escape" ];
        })) "an unsafe removeFiles path should fail"
        && lib.assertMsg (hasFailure "same target" (failingAssertions {
          files.game.place = {
            "a".target = "shared.dll";
            "b".target = "shared.dll";
          };
          files.game.place."a".source = fakeArt;
          files.game.place."b".source = fakeArt;
        })) "duplicate resolved targets should fail"
        && lib.assertMsg (hasFailure "dllOverrides and env.WINEDLLOVERRIDES" (failingAssertions {
          dllOverrides.winhttp = "n,b";
          env.WINEDLLOVERRIDES = "d3d11=n";
        })) "setting both dllOverrides and a different env.WINEDLLOVERRIDES should fail"
        && lib.assertMsg (hasFailure "both places and patches" (failingAssertions {
          files.game.place."config/x.ini".source = fakeArt;
          files.game.patch."config/x.ini" = {
            format = "ini";
            content.A.b = 1;
          };
        })) "placing and patching the same file should fail"
        && lib.assertMsg (hasFailure "invalid systemd.target.name" (failingAssertions {
          systemd = {
            enable = true;
            target.name = "not valid";
          };
        })) "an invalid systemd.target.name should fail"
        && lib.assertMsg (
          failingAssertions {
            files.game.place."mods/ok.pak".source = fakeArt;
            files.game.remove = [ "movies/intro.bik" ];
            files.game.patch."config/ok.ini" = {
              format = "ini";
              content.A.b = 1;
            };
          } == [ ]
        ) "a valid file config should not fail";
    in
    {
      checks = {
        systemd-targets =
          let
            eval = inputs.nixpkgs.lib.nixosSystem {
              modules = [
                self.nixosModules.default
                {
                  system.stateVersion = "26.05";
                  nixpkgs.hostPlatform = system;
                  programs.steam.config = {
                    enable = true;
                    apps = {
                      "438100" = {
                        name = "VRChat";
                        systemd = {
                          enable = true;
                          scope.properties.Slice = "games.slice";
                        };
                      };
                      "1002" = {
                        name = ''Sven "Co-op"'';
                        systemd = {
                          enable = true;
                          target.name = "sven-co-op";
                        };
                      };
                      "220" = { };
                    };
                  };
                }
              ];
            };

            steamConfig = eval.config.programs.steam.config;
            units = eval.config.systemd.user.units;
            appTarget = pkgs.writeText "app-target" units."steam-app-vrchat.target".text;
            sharedTarget = pkgs.writeText "shared-target" units."steam-app.target".text;
            wrapper = steamConfig.apps."438100".wrapper.package;
            quotedNameWrapper = steamConfig.apps."1002".wrapper.package;
          in
          pkgs.runCommand "systemd-targets" { } (
            assert lib.assertMsg (
              steamConfig.apps."220".wrapper.package == null
            ) "an app with no options must not get a wrapper";
            ''
              grep -q 'Description=VRChat' ${appTarget}
              grep -q 'StopWhenUnneeded=yes' ${appTarget}
              grep -q 'RefuseManualStart=yes' ${appTarget}
              grep -q 'Wants=steam-app.target' ${appTarget}
              grep -q 'After=steam-app.target' ${appTarget}
              grep -q 'StopWhenUnneeded=yes' ${sharedTarget}

              wrapper=${wrapper}/bin/steam-app-wrapper-438100
              grep -q 'systemd-run --user --scope' "$wrapper"
              grep -q 'property=Wants=steam-app-vrchat.target' "$wrapper"
              grep -q 'property=Slice=games.slice' "$wrapper"

              quoted=${quotedNameWrapper}/bin/steam-app-wrapper-1002
              grep -q "scn_app_name='Sven" "$quoted"
              grep -q 'launching ''$scn_app_name without a scope' "$quoted"

              touch $out
            ''
          );

        steam-config-patcher = self.packages.${system}.steam-config-patcher;

        patcher-integration =
          pkgs.runCommand "patcher-integration"
            { nativeBuildInputs = [ self.packages.${system}.steam-config-patcher ]; }
            ''
              export HOME="$PWD/home"
              steam="$HOME/.local/share/Steam"
              install="$steam/steamapps/common/Test Game"
              mkdir -p "$steam/config" "$steam/userdata/111/config" "$steam/steamapps" "$install" "$steam/steamapps/compatdata/620/pfx"
              cp ${seedConfigVdf} "$steam/config/config.vdf"
              cp ${seedLocalconfigVdf} "$steam/userdata/111/config/localconfig.vdf"
              cp ${seedAppmanifest} "$steam/steamapps/appmanifest_620.acf"
              echo unwanted > "$install/unwanted.txt"

              steam-config-patcher ${patcherInput}

              acf="$steam/steamapps/appmanifest_620.acf"
              lc="$steam/userdata/111/config/localconfig.vdf"

              grep -q GE-Proton "$steam/config/config.vdf"
              grep -q test-launch-wrapper "$lc"
              grep -q '"displayratesasbits"[[:space:]]*"1"' "$lc"
              grep -q '"BetaKey"' "$acf"
              grep -q beta "$acf"
              grep -q german "$acf"
              grep -q AutoUpdateBehavior "$acf"
              grep -q AllowOtherDownloadsWhileRunning "$acf"
              test -f "$steam/userdata/111/config/steam-config-nix-manifest.json"

              grep -q modcontent "$install/mods/test.txt"
              test ! -e "$install/unwanted.txt"
              test -f "$steam/config/steam-config-nix-files.json"

              grep -q Fullscreen "$install/config/game.ini"

              grep -q hard "$install/config/game.vdf"

              pfx="$steam/steamapps/compatdata/620/pfx"
              grep -q 'dword:00000000' "$pfx/system.reg"
              grep -Fq '"MaxVersionGL"="3.2"' "$pfx/system.reg"

              # unity hashes the pref key
              grep -Fq 'Software\\TestCo\\TestGame' "$pfx/user.reg"
              grep -q 'MirrorResolution_h' "$pfx/user.reg"
              grep -q 'dword:00000002' "$pfx/user.reg"
              grep -Fq 'hex(4):00,00,00,00,00,00,e0,3f' "$pfx/user.reg"

              grep -Fq 'fps_max "400"' "$install/cfg/autoexec.cfg"
              grep -Fq 'cl_crosshair_recoil "0"' "$install/cfg/autoexec.cfg"

              # second run must be idempotent
              steam-config-patcher ${patcherInput}

              grep -q modcontent "$install/mods/test.txt"

              touch $out
            '';

        module-assertions = pkgs.runCommand "module-assertions-check" { } (
          assert assertionsOk;
          "touch $out"
        );

        compat-tool-bin-layout =
          let
            eval = inputs.nixpkgs.lib.nixosSystem {
              modules = [
                self.nixosModules.default
                {
                  system.stateVersion = "26.05";
                  nixpkgs.hostPlatform = system;
                  programs.steam.config = {
                    enable = true;
                    defaultCompatTool = fakeBinCompatTool;
                  };
                }
              ];
            };
            execStart = eval.config.systemd.services."steam-config-patcher@".serviceConfig.ExecStart;
          in
          pkgs.runCommand "compat-tool-bin-layout"
            {
              nativeBuildInputs = [
                self.packages.${system}.steam-config-patcher
                pkgs.jq
                pkgs.python3
              ];
            }
            ''
              cfg=$(python3 -c 'import shlex,sys; print(shlex.split(sys.argv[1])[1])' ${lib.escapeShellArg execStart})
              path=$(jq -r .defaultCompatTool.path "$cfg")

              test -f "$path/compatibilitytool.vdf"
              test "$path" != "${fakeBinCompatTool}"
              grep -q Bin-Proton "$path/compatibilitytool.vdf"

              export HOME="$PWD/home"
              steam="$HOME/.local/share/Steam"
              mkdir -p "$steam/config" "$steam/userdata/1/config"
              echo '"InstallConfigStore" { "Software" { "Valve" { "Steam" { "CompatToolMapping" { } } } } }' > "$steam/config/config.vdf"
              echo '"UserLocalConfigStore" { "Software" { "Valve" { "Steam" { "Apps" { } } } } }' > "$steam/userdata/1/config/localconfig.vdf"
              steam-config-patcher "$cfg"
              grep -q Bin-Proton "$steam/config/config.vdf"

              touch $out
            '';

        nixos-module = pkgs.runCommand "nixos-module-check" { } ''
          diff ${expectedJson} ${actualJson}

          # steps with working variables are functions, so match those lines indented
          stepLine() {
            sed 's/^[[:space:]]*//' "$2" | grep -Fx "$1"
          }

          grep -Fx 'exec env MANGOHUD=1 "$@" -vulkan' ${strWrapper}

          # rawLaunchOptions with no %command% is appended as args to the game
          grep -Fx 'exec env "$@" -windowed -novid' ${rawArgsWrapper}

          # winetricks step runs before the launch, guarded by the prefix + a marker
          grep -F 'STEAM_COMPAT_DATA_PATH/pfx' ${strWrapper}
          grep -F 'protontricks' ${strWrapper}
          grep -F 'vcrun2022' ${strWrapper}

          # a relocated prefix is bound over the path steam picked, for protontricks
          grep -F -- '--bind "$STEAM_COMPAT_DATA_PATH" "$scn_compat_orig"' ${strWrapper}
          stepLine 'export STEAM_COMPAT_DATA_PATH="$dir"' ${strWrapper}

          # step working variables are function local, so preHook cannot see them
          stepLine 'local dir parent' ${strWrapper}
          stepLine 'local marker want' ${strWrapper}

          grep -Fx 'export WINEDLLOVERRIDES="version=n,b;winmm=n,b"' ${optionsWrapper}
          grep -Fx 'unset TZ' ${optionsWrapper}
          grep -Fx 'declare -a wrappers=(gamemoderun)' ${optionsWrapper}
          grep -Fx 'declare -a args=(--launcher-skip)' ${optionsWrapper}
          grep -Fx 'echo prehook' ${optionsWrapper}

          grep -FxR 'Exec=steam steam://rungameid/620' ${desktopItemsDir}/share/applications
          grep -FxR 'Exec=steam steam://rungameid/1091500' ${desktopItemsDir}/share/applications
          grep -FxR 'Icon=steam-config-nix-1091500' ${desktopItemsDir}/share/applications
          grep -FxR 'Icon=custom-icon' ${desktopItemsDir}/share/applications/steam-config-nix-620.desktop
          # non-steam app: 64 bit shortcut game id (id << 32 | 0x02000000)
          grep -FxR 'Exec=steam steam://rungameid/15174691026754338816' ${desktopItemsDir}/share/applications
          test ! -e ${desktopItemsDir}/share/applications/steam-config-nix-730.desktop
          test ! -e ${desktopItemsDir}/share/applications/steam-config-nix-999.desktop

          touch $out
        '';

        docs-options = pkgs.runCommand "check-docs-options" { nativeBuildInputs = [ pkgs.python3 ]; } ''
          python3 ${./docs-options.py} ${self'.packages.docs.optionsJson} ${../docs/content}
          touch $out
        '';

        formatting = pkgs.runCommand "check-formatting" { nativeBuildInputs = [ pkgs.nixfmt ]; } ''
          nixfmt --check $(find ${self} -name '*.nix')
          touch $out
        '';

        mypy =
          pkgs.runCommand "mypy-check"
            {
              nativeBuildInputs = [
                (pkgs.python3.withPackages (
                  ps: with ps; [
                    mypy
                    pydantic
                    psutil
                    pillow
                    types-psutil
                  ]
                ))
              ];
            }
            ''
              cp -r ${../patcher} patcher
              chmod -R u+w patcher
              cd patcher
              mypy steam_config_patcher
              touch $out
            '';
      };
    };
}
