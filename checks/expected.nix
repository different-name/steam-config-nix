{
  fakeCompatTool,
  fakeArt,
  noArtwork,
}:
{
  apps = {
    "620" = {
      id = 620;
      prefixPath = "/mnt/prefixes/620";
      compatTool = null;
      betaBranch = null;
      language = null;
      updateBehavior = null;
      allowDownloadsWhileRunning = null;
      libraryIcon = false;
      launchOptions = "/bin/sh -c 'if [ -x \"$0\" ]; then exec \"$0\" \"$@\"; else exec \"$@\"; fi' /var/lib/steam-config-nix/apps/620/wrapper %command%";
      artwork = noArtwork;
      files = [ ];
      removeFiles = [ ];
      patches = [ ];
    };

    "440" = {
      id = 440;
      prefixPath = null;
      compatTool = null;
      betaBranch = null;
      language = null;
      updateBehavior = null;
      allowDownloadsWhileRunning = null;
      libraryIcon = true;
      launchOptions = "/bin/sh -c 'if [ -x \"$0\" ]; then exec \"$0\" \"$@\"; else exec \"$@\"; fi' /var/lib/steam-config-nix/apps/440/wrapper %command%";
      artwork = noArtwork;
      files = [ ];
      removeFiles = [ ];
      patches = [ ];
    };

    "730" = {
      id = 730;
      prefixPath = null;
      compatTool = fakeCompatTool;
      betaBranch = null;
      language = null;
      updateBehavior = null;
      allowDownloadsWhileRunning = null;
      libraryIcon = false;
      launchOptions = null;
      artwork = noArtwork;
      files = [ ];
      removeFiles = [ ];
      patches = [ ];
    };

    "999" = {
      id = 999;
      prefixPath = null;
      compatTool = null;
      betaBranch = null;
      language = null;
      updateBehavior = null;
      allowDownloadsWhileRunning = null;
      libraryIcon = true;
      launchOptions = null;
      artwork = noArtwork;
      files = [ ];
      removeFiles = [ ];
      patches = [ ];
    };

    "1091500" = {
      id = 1091500;
      prefixPath = null;
      compatTool = "proton_experimental";
      betaBranch = "prerelease";
      language = "german";
      updateBehavior = "1";
      allowDownloadsWhileRunning = "1";
      libraryIcon = true;
      launchOptions = "/bin/sh -c 'if [ -x \"$0\" ]; then exec \"$0\" \"$@\"; else exec \"$@\"; fi' /var/lib/steam-config-nix/apps/1091500/wrapper %command%";
      artwork = noArtwork // {
        hero = fakeArt;
      };
      files = [
        {
          location = "game";
          target = "mods/test.pak";
          source = "${fakeArt}";
          mode = "enforce";
          executable = null;
        }
      ];
      removeFiles = [
        {
          location = "game";
          target = "movies/intro.bik";
        }
      ];
      patches = [
        {
          location = "game";
          target = "config/user.ini";
          format = "ini";
          content = {
            Video = {
              Fullscreen = 1;
            };
          };
          createIfMissing = false;
        }
      ];
    };
  };

  nonSteamApps = {
    vintage-story = {
      id = 3533133079;
      prefixPath = null;
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
}
