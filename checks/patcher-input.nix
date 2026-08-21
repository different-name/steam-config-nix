{ pkgs, seedModFile }:
pkgs.writeText "patcher-input.json" (
  builtins.toJSON {
    onSteamRunning = "wait";
    defaultCompatTool = null;
    displayRatesAsBits = true;
    apps."Test Game" = {
      id = 620;
      compatTool = "GE-Proton";
      launchOptions = "test-launch-wrapper %command%";
      betaBranch = "beta";
      language = "german";
      updateBehavior = "1";
      allowDownloadsWhileRunning = "2";
      artwork = {
        cover = null;
        header = null;
        hero = null;
        logo = null;
      };
      files = [
        {
          location = "game";
          target = "mods/test.txt";
          source = "${seedModFile}";
          mode = "enforce";
          executable = null;
        }
      ];
      removeFiles = [
        {
          location = "game";
          target = "unwanted.txt";
        }
      ];
      patches = [
        {
          location = "game";
          target = "config/game.ini";
          format = "ini";
          content = {
            Video = {
              Fullscreen = 1;
            };
          };
          createIfMissing = true;
        }
        {
          location = "game";
          target = "config/game.vdf";
          format = "keyvalue";
          content = {
            Settings = {
              Difficulty = "hard";
            };
          };
          createIfMissing = true;
        }
        {
          location = "prefix";
          target = "system.reg";
          format = "registry";
          content = {
            "Software\\Wine\\Direct3D" = {
              csmt = 0;
              MaxVersionGL = "3.2";
            };
          };
          createIfMissing = true;
        }
        {
          location = "prefix";
          target = "user.reg";
          format = "unityPrefs";
          content = {
            "Software\\TestCo\\TestGame" = {
              MirrorResolution = 2;
              MirrorScale = 0.5;
            };
          };
          createIfMissing = true;
        }
        {
          location = "game";
          target = "cfg/autoexec.cfg";
          format = "sourceConvars";
          content = {
            fps_max = 400;
            cl_crosshair_recoil = false;
          };
          createIfMissing = true;
        }
      ];
    };
    nonSteamApps = { };
  }
)
