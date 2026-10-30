{
  self,
  pkgs,
  system,
}:
let
  launch = self.packages.${system}.steam-config-launch;
  layer = pkgs.runCommand "vm-layer" { } ''
    mkdir -p $out/mods $out/bin $out/BepInEx/core
    echo hi > $out/mods/x.txt
    printf '#!/bin/sh\necho tool\n' > $out/bin/tool
    chmod +x $out/bin/tool
    echo core > $out/BepInEx/core/a.dll
  '';
  layerWithoutX = pkgs.runCommand "vm-layer-without-x" { } ''
    cp -r ${layer} $out
    chmod -R u+w $out
    rm $out/mods/x.txt
  '';
  rootLayer = pkgs.runCommand "vm-root-layer" { } ''
    mkdir -p $out
    echo proxy > $out/winhttp.dll
  '';
  prefixLayer = pkgs.runCommand "vm-prefix-layer" { } ''
    mkdir -p $out/drive_c/tools
    echo ytdlp > $out/drive_c/tools/yt-dlp.exe
  '';
  seed = pkgs.writeText "seed.cfg" "seeded";
  entry = target: readOnly: { inherit target readOnly; };
  location =
    {
      layer,
      overlay,
      hide ? [ ],
      passthrough ? [ ],
      writeDefault ? [ ],
      writeKeys ? [ ],
    }:
    {
      layer = "${layer}";
      inherit
        overlay
        hide
        passthrough
        writeDefault
        writeKeys
        ;
    };
  game =
    served:
    location {
      inherit (served) layer overlay;
      hide = [ "movies/intro.bik" ];
      passthrough = [ "Saves" ];
      writeDefault = [
        {
          target = "BepInEx/config/a.cfg";
          source = "${seed}";
          executable = null;
        }
      ];
      writeKeys = [
        {
          target = "Engine.ini";
          format = "ini";
          content."Engine.Console".ConsoleKey = "F9";
          createIfMissing = false;
        }
      ];
    };
  full = {
    inherit layer;
    overlay = [
      (entry "mods/x.txt" false)
      (entry "bin/tool" true)
      (entry "BepInEx/core" false)
    ];
  };
  withoutX = {
    layer = layerWithoutX;
    overlay = [
      (entry "bin/tool" true)
      (entry "BepInEx/core" false)
    ];
  };
  prefix = location {
    layer = prefixLayer;
    overlay = [ (entry "drive_c/tools/yt-dlp.exe" false) ];
  };
  mkSpec =
    {
      bwrap ? "${pkgs.bubblewrap}/bin/bwrap",
      key ? "vmtest",
      locations,
    }:
    pkgs.writeText "spec.json" (
      pkgs.lib.toJSON {
        inherit key bwrap locations;
        name = "VM test";
        appId = null;
        notifySend = null;
      }
    );
  spec = mkSpec {
    locations = {
      game = game full;
      inherit prefix;
    };
  };
  specWithoutX = mkSpec {
    locations = {
      game = game withoutX;
      inherit prefix;
    };
  };
  rootSpec = mkSpec {
    key = "vmroot";
    locations.game = location {
      layer = rootLayer;
      overlay = [ (entry "winhttp.dll" false) ];
      passthrough = [ "Saves" ];
    };
  };
  brokenSpec = mkSpec {
    bwrap = "${pkgs.coreutils}/bin/false";
    locations.game = game full;
  };
  launchExe = pkgs.lib.getExe launch;
  launchSpec =
    id: extra:
    pkgs.writeText "launch-${toString id}.json" (
      pkgs.lib.toJSON (
        {
          version = 1;
          key = "vmtest";
          appId = id;
          kind = "steam";
          name = "VM test";
          notifySend = null;
          env = { };
          dllOverrides = { };
          args = [ ];
          wrappers = [ ];
        }
        // extra
      )
    );
  shellSpec = launchSpec 4000 {
    env.SCN_VM = "1";
    preHook = "export HOOK=1";
    shell = pkgs.lib.getExe pkgs.bash;
    files = "${spec}";
  };
  scopeSpec = launchSpec 4001 {
    scope = {
      systemdRun = pkgs.lib.getExe' pkgs.systemd "systemd-run";
      systemctl = pkgs.lib.getExe' pkgs.systemd "systemctl";
      properties = {
        CPUWeight = "150";
        Description = "VM test";
      };
    };
  };
  scopeScript = pkgs.writeShellScript "files-vm-scope" ''
    set -eux
    export PATH=${
      pkgs.lib.makeBinPath [
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.systemd
      ]
    }:''${PATH-}
    cd /home/alice
    data=/home/alice/scope/steam-config-nix
    mkdir -p $data/launch
    touch $data/state.json
    ln -sfn ${launchExe} $data/launch-shell
    ln -sfn ${scopeSpec} $data/launch/4001.json
    export XDG_DATA_HOME=/home/alice/scope SteamAppId=4001
    $data/launch-shell 'set -e; grep -q "/app-steam-4001-$$.scope$" /proc/self/cgroup; test "$STEAM_LAUNCH_WRAPPER_SCOPE" = 0; touch started; for i in $(seq 120); do test -e release && exit 0; sleep 0.5; done; exit 1' &
    pid=$!
    for i in $(seq 120); do test -e started && break; sleep 0.5; done
    test -e started
    test "$(systemctl --user show -p CPUWeight --value app-steam-4001-$pid.scope)" = 150
    touch release
    wait $pid
    echo "scope passed"
  '';
  noScopeScript = pkgs.writeShellScript "files-vm-no-scope" ''
    set -eux
    cd /home/alice
    export XDG_RUNTIME_DIR=/run/user/1001 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1001/bus XDG_DATA_HOME=/home/alice/scope SteamAppId=4001
    out=$(scope/steam-config-nix/launch-shell 'set -e; if grep -q app-steam- /proc/self/cgroup; then exit 1; fi; echo "scope=''${STEAM_LAUNCH_WRAPPER_SCOPE-unset}"' 2>err)
    test "$out" = scope=unset
    grep -q 'No systemd user manager, launching VM test without a scope' err
    echo "no scope passed"
  '';
  script = pkgs.writeShellScript "files-vm-test" ''
    set -eux
    cd "$HOME"
    export STEAM_COMPAT_INSTALL_PATH="$HOME/game" STEAM_COMPAT_DATA_PATH="$HOME/compat" XDG_DATA_HOME="$HOME/data" XDG_RUNTIME_DIR="$HOME/run"
    mkdir -p game/movies/extra run compat/pfx/drive_c
    echo v1 > game/real.txt
    echo v1 > game/movies/credits.txt
    echo intro > game/movies/intro.bik
    echo old > game/movies/extra/old
    printf '[Engine.Console]\nConsoleKey = Tilde\n' > game/Engine.ini
    cp -r game game.before
    run() { ${pkgs.lib.getExe launch} launch ${spec} -- sh -ec "$1"; }

    echo "== the game's exit status is passed on"
    if run false; then exit 1; fi

    echo "== merged view"
    run 'cd game; test "$(cat mods/x.txt)" = hi; test ! -e movies/intro.bik; test -e real.txt; test "$(cat BepInEx/core/a.dll)" = core; ./bin/tool | grep -qx tool'
    run 'test "$(cat compat/pfx/drive_c/tools/yt-dlp.exe)" = ytdlp'
    run 'test "$(cat game/BepInEx/config/a.cfg)" = seeded; grep -qx "ConsoleKey = F9" game/Engine.ini'
    run 'test "$(findmnt -rn -o FSTYPE -T game/mods/x.txt)" = overlay; test "$(findmnt -rn -o FSTYPE -T game/real.txt)" != overlay'
    run 'test "$(ls /proc/self/fd | awk "\$1 > 3" | wc -l)" = 0'
    test -d game/BepInEx
    test ! -e game/BepInEx/config
    test ! -e compat/pfx/drive_c/tools/yt-dlp.exe
    grep -qx "ConsoleKey = F9" game/Engine.ini
    grep -qx "ConsoleKey = Tilde" data/steam-config-nix/apps/vmtest/originals/game/Engine.ini
    cp game/Engine.ini game.before/Engine.ini

    echo "== writes persist in the upper"
    run 'echo data > game/BepInEx/config/g.cfg; echo s > game/Saves/s.dat'
    run 'test "$(cat game/BepInEx/config/g.cfg)" = data'
    test ! -e game/BepInEx/config
    test "$(cat data/steam-config-nix/apps/vmtest/writes/game/BepInEx/config/g.cfg)" = data
    test "$(cat game/Saves/s.dat)" = s

    echo "== the declaration wins"
    run 'echo changed > game/mods/x.txt; test "$(cat game/mods/x.txt)" = changed'
    run 'test "$(cat game/mods/x.txt)" = hi'

    echo "== the game's own files inside a served directory stay"
    run 'echo state > game/BepInEx/core/state.json; echo mine > game/BepInEx/core/a.dll'
    run 'test "$(cat game/BepInEx/core/state.json)" = state; test "$(cat game/BepInEx/core/a.dll)" = core'

    echo "== a file that is no longer served is gone, the game's edit with it"
    run 'echo edited >> game/mods/x.txt'
    ${pkgs.lib.getExe launch} launch ${specWithoutX} -- sh -ec 'test ! -e game/mods/x.txt; test "$(cat game/BepInEx/core/a.dll)" = core'
    run 'test "$(cat game/mods/x.txt)" = hi'

    echo "== a changed real file drops its copy"
    run 'echo mine >> game/movies/credits.txt'
    run 'test "$(cat game/movies/credits.txt)" = "v1
    mine"'
    echo v2 > game/movies/credits.txt
    echo v2 > game.before/movies/credits.txt
    run 'test "$(cat game/movies/credits.txt)" = v2'

    echo "== a recreated directory no longer hides real files"
    run 'rm -rf game/movies/extra; mkdir game/movies/extra; touch game/movies/extra/new; test ! -e game/movies/extra/old'
    run 'test -e game/movies/extra/old; test -e game/movies/extra/new'

    echo "== readOnly refuses a replacement"
    run 'echo y > game/tmp; if mv -f game/tmp game/bin/tool; then exit 1; fi; rm game/tmp; test "$(./game/bin/tool)" = tool'

    echo "== passthrough under a root level overlay"
    ${pkgs.lib.getExe launch} launch ${rootSpec} -- sh -ec 'test "$(cat game/winhttp.dll)" = proxy; test "$(findmnt -rn -o FSTYPE -T game/real.txt)" = overlay; test "$(findmnt -rn -o FSTYPE -T game/Saves)" != overlay; echo r > game/Saves/r.dat'
    test "$(cat game/Saves/r.dat)" = r
    test ! -e data/steam-config-nix/apps/vmroot/writes/game/Saves

    echo "== the real install is untouched"
    rm -r game/Saves game/BepInEx game/mods game/bin
    diff -r game.before game

    echo "== fallbacks launch plainly"
    ${pkgs.lib.getExe launch} launch ${brokenSpec} -- sh -ec 'test ! -e game/mods/x.txt; test ! -e game/BepInEx/config'
    ( flock -x 9; sleep 5 ) 9> data/steam-config-nix/apps/vmtest/lock &
    sleep 1
    run 'test ! -e game/mods/x.txt'
    wait

    echo "== shell mode runs the files step from the app spec"
    mkdir -p data/steam-config-nix/launch
    touch data/steam-config-nix/state.json
    ln -s ${launchExe} data/steam-config-nix/launch-shell
    ln -s ${shellSpec} data/steam-config-nix/launch/4000.json
    SteamAppId=4000 data/steam-config-nix/launch-shell 'set -e; test "$(findmnt -rn -o FSTYPE -T game/mods/x.txt)" = overlay; test "$(cat game/mods/x.txt)" = hi; test "$SCN_VM" = 1; test "$HOOK" = 1'
    test ! -e game/mods/x.txt
    echo "all passed"
  '';
in
pkgs.testers.runNixOSTest {
  name = "files-vm";
  nodes.machine = {
    users.users.alice = {
      isNormalUser = true;
      uid = 1001;
      linger = true;
    };
    environment.systemPackages = [ pkgs.util-linux ];
  };
  testScript = ''
    def run(command):
        status, out = machine.execute(f"{command} 2>&1")
        print(out)
        assert status == 0, f"exit {status}"

    machine.wait_for_unit("multi-user.target")
    run("su alice -c ${script}")
    machine.wait_for_unit("user@1001.service")
    run("runuser -u alice -- env XDG_RUNTIME_DIR=/run/user/1001 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1001/bus systemd-run --user --wait --pipe --quiet --collect ${scopeScript}")
    machine.succeed("systemctl stop user@1001.service")
    run("su alice -c ${noScopeScript}")
  '';
}
