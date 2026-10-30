{
  self,
  pkgs,
  system,
}:
let
  patcher = "${self.packages.${system}.steam-config-patcher}/bin/steam-config-patcher";
  cover = pkgs.writeText "cover.png" "art";
  icon = pkgs.writeText "icon.png" "icon";
  compatTool = pkgs.writeTextDir "compatibilitytool.vdf" ''
    "compatibilitytools"
    {
      "compat_tools"
      {
        "scn_tool"
        {
          "install_path" "."
          "display_name" "SCN tool"
          "from_oslist" "windows"
          "to_oslist" "linux"
        }
      }
    }
  '';
  fakeData = pkgs.runCommand "vm-fakedata" { nativeBuildInputs = [ pkgs.imagemagick ]; } ''
    mkdir -p $out/icons/hicolor/32x32/apps
    magick -size 32x32 xc:red $out/icons/hicolor/32x32/apps/steam.png
  '';
  fakeSteam = pkgs.writeShellScript "fake-steam" ''
    if [ "$1" = -shutdown ]; then
      ${pkgs.procps}/bin/pkill -x -u alice steam || true
    fi
  '';
  steamTree = pkgs.runCommand "vm-steam-tree" { } ''
    mkdir -p $out/config $out/userdata/1/config $out/steamapps
    cat > $out/config/config.vdf <<'EOF'
    "InstallConfigStore"
    {
      "Accessibility"
      {
        "DesktopUIScale" "1"
      }
      "Software"
      {
        "Valve"
        {
          "Steam"
          {
            "CompatToolMapping"
            {
              "620"
              {
                "config" ""
                "name" "user_tool"
                "priority" "250"
              }
            }
          }
        }
      }
    }
    EOF
    cat > $out/config/libraryfolders.vdf <<'EOF'
    "libraryfolders"
    {
      "0"
      {
        "path" "/home/alice/.local/share/Steam"
        "label" ""
      }
    }
    EOF
    cat > $out/userdata/1/config/localconfig.vdf <<'EOF'
    "UserLocalConfigStore"
    {
      "Software"
      {
        "Valve"
        {
          "Steam"
          {
            "apps"
            {
              "620"
              {
                "LaunchOptions" "/bin/sh -c x /var/lib/steam-config-nix/apps/620/wrapper %command%"
              }
            }
          }
        }
      }
      "system"
      {
        "displayratesasbits" "0"
      }
    }
    EOF
    cat > $out/steamapps/appmanifest_620.acf <<'EOF'
    "AppState"
    {
      "appid" "620"
      "AutoUpdateBehavior" "0"
      "UserConfig"
      {
        "language" "english"
      }
    }
    EOF
  '';
  mkState =
    name: attrs:
    pkgs.writeText "${name}.json" (
      pkgs.lib.toJSON (
        {
          steam = "${fakeSteam}";
          notifySend = null;
        }
        // attrs
      )
    );
  full = scale: {
    onSteamRunning = "wait";
    desktopUiScale = scale;
    displayRatesAsBits = true;
    libraryFolders = [ "/home/alice/lib2" ];
    globalCompatTool = "GE-Proton";
    apps."620" = {
      compatTool.path = "${compatTool}";
      beta = "prerelease";
      language = "german";
      updateBehavior = 1;
      backgroundDownloads = 2;
      overlay = false;
      steamInput = 2;
      libraryIcon = true;
      artwork.cover = "${cover}";
    };
    shortcuts."4132570534" = {
      name = "probe";
      exe = "/opt/probe/run";
      dir = "/opt/probe";
      vr = true;
      overlay = false;
      hidden = true;
      icon = "${icon}";
    };
  };
  stateA = mkState "state-a" (full 1.25);
  stateA2 = mkState "state-a2" (full 1.5);
  stateA3 = mkState "state-a3" (full 1.75);
  stateS = mkState "state-s" (full 1.5 // { onSteamRunning = "skip"; });
  stateB = mkState "state-b" {
    onSteamRunning = "close";
    apps = { };
    shortcuts = { };
    libraryFolders = [ ];
  };
  script = pkgs.writeShellScript "patcher-vm-test" ''
    set -eux
    cd "$HOME"
    export XDG_DATA_DIRS="$HOME/fakedata"
    export LC_ALL=C
    ln -s ${fakeData} fakedata
    mkdir -p bin .steam .local/share
    printf '#!/bin/sh\nsleep "$1"\n' > bin/steam
    chmod +x bin/steam
    cp -r ${steamTree} .local/share/Steam
    chmod -R u+w .local/share/Steam
    ln -s "$HOME/.local/share/Steam" .steam/root
    steam=$HOME/.local/share/Steam
    config=$steam/config/config.vdf
    local=$steam/userdata/1/config/localconfig.vdf
    manifest=$steam/steamapps/appmanifest_620.acf
    folders=$steam/config/libraryfolders.vdf
    shortcuts=$steam/userdata/1/config/shortcuts.vdf
    grid=$steam/userdata/1/config/grid
    prior=$HOME/.local/share/steam-config-nix/prior.json
    managedIcon=$HOME/.local/share/icons/hicolor/32x32/apps/steam-config-nix-620.png
    run() { ${patcher} "$@" 2>err; cat err; }
    present() { grep -qE "$@"; }
    absent() { if grep -E "$@"; then echo "unexpected match: $*"; exit 1; fi; }
    count() { grep -ac "$1" "$2" || true; }

    echo "== first run applies everything"
    run ${stateA}
    present '"DesktopUIScale"\s*"1.25"' "$config"
    present '"name"\s*"scn_tool"' "$config"
    absent 'user_tool' "$config"
    present '"displayratesasbits"\s*"1"' "$local"
    present '"OverlayAppEnable"\s*"0"' "$local"
    present '"LaunchOptions"\s*""' "$local"
    present '"BetaKey"\s*"prerelease"' "$manifest"
    present '"path"\s*"/home/alice/lib2"' "$folders"
    test -d lib2
    test "$(count AppName "$shortcuts")" = 1
    grep -qaP '\x02appid\x00\xa6\x05\x52\xf6' "$shortcuts"
    test "$(readlink "$grid/620p.png")" = ${cover}
    test -f "$managedIcon"
    jq -e '.keys | map(select(.file == "config" and .path[-1] == "620")) | .[0].prior.name == "user_tool"' "$prior"
    jq -e '.shortcuts."1" == [4132570534] and .libraryFolders == ["/home/alice/lib2"]' "$prior"

    echo "== a second run writes nothing"
    cp -r "$steam" steam.before
    run ${stateA}
    grep -q 'already match' err
    diff -r steam.before "$steam"
    rm -r steam.before

    echo "== wait holds the writes until steam exits"
    bin/steam 300 &
    sleeper=$!
    sleep 1
    ln -sfn ${stateA2} state.json
    ${patcher} state.json 2>err3 &
    waiting=$!
    sleep 3
    present '"DesktopUIScale"\s*"1.25"' "$config"
    grep -q 'waiting for it to exit' err3
    ln -sfn ${stateA3} state.json
    pkill -x -u alice steam
    wait $waiting
    wait $sleeper || true
    present '"DesktopUIScale"\s*"1.75"' "$config"

    echo "== close shuts steam down"
    bin/steam 300 &
    sleeper=$!
    sleep 1
    run ${stateB}
    if pgrep -x -u alice steam; then exit 1; fi
    wait $sleeper || true

    echo "== removal restores prior values"
    present '"DesktopUIScale"\s*"1"' "$config"
    present '"name"\s*"user_tool"' "$config"
    present '"displayratesasbits"\s*"0"' "$local"
    absent OverlayAppEnable "$local"
    absent BetaKey "$manifest"
    absent lib2 "$folders"
    test -d lib2
    test "$(count AppName "$shortcuts")" = 0
    test ! -e "$grid/620p.png"
    test ! -e "$managedIcon"
    jq -e '.keys == [] and .shortcuts."1" == [] and .libraryFolders == []' "$prior"

    echo "== a value the user changed is left alone"
    run ${stateA}
    sed -i 's/"DesktopUIScale"\(\s*\)"1.25"/"DesktopUIScale"\1"2"/' "$config"
    run ${stateB}
    present '"DesktopUIScale"\s*"2"' "$config"
    jq -e '[.keys[] | select(.path[-1] == "DesktopUIScale")] == []' "$prior"

    echo "== skip leaves the files and says so"
    run ${stateA}
    jq -e '.keys | length > 0' "$prior"
    cp "$config" config.before
    cp "$local" local.before
    bin/steam 300 &
    sleeper=$!
    sleep 1
    run ${stateS}
    grep -q 'next activation' err
    cmp config.before "$config"
    cmp local.before "$local"
    present '"DesktopUIScale"\s*"1.25"' "$config"
    jq -e '(.keys | length > 0) and .shortcuts."1" == [4132570534]' "$prior"
    test -L "$grid/620p.png"
    pkill -x -u alice steam
    wait $sleeper || true
    run ${stateB}
    jq -e '.keys == []' "$prior"

    echo "== a missing steam dir is not a failure"
    mkdir empty
    HOME=$HOME/empty run ${stateA}
    grep -q 'has not been run' err

    echo "== concurrent runs"
    ( flock -x 9; sleep 5 ) 9> .local/share/steam-config-nix/patcher.lock &
    sleep 1
    run ${stateA}
    grep -q 'another run' err
    echo "all passed"
  '';
in
pkgs.testers.runNixOSTest {
  name = "steam-config-patcher";
  nodes.machine = {
    users.users.alice = {
      isNormalUser = true;
      uid = 1001;
    };
    environment.systemPackages = [
      pkgs.util-linux
      pkgs.jq
      pkgs.procps
      pkgs.diffutils
    ];
  };
  testScript = ''
    machine.wait_for_unit("multi-user.target")
    status, out = machine.execute("su alice -c ${script} 2>&1")
    print(out)
    assert status == 0, f"exit {status}"
  '';
}
