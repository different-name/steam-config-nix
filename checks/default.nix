{
  self,
  nixpkgs,
  home-manager,
  pkgs,
  system,
}:
let
  inherit (nixpkgs) lib;

  art = pkgs.writeText "cover.png" "art";

  sample = {
    programs.steam-config = {
      enable = true;
      env.PROTON_ENABLE_WAYLAND = 1;
      defaultCompatTool = "GE-Proton";
      desktopUiScale = 1.25;
      desktopEntries.enable = true;
      libraryFolders = [ "/mnt/games" ];
      apps."105600" = {
        overlay = false;
        steamInput = "enable";
        env.SCN = "x";
        args = [
          "-a"
          "two words"
        ];
        systemd.enable = true;
        artwork.cover = art;
        files.game = {
          overlay."mods/x.txt".text = "hi";
          overlay."bin/tool" = {
            source = art;
            executable = true;
            readOnly = true;
          };
          hide = [ "movies/intro.bik" ];
          passthrough = [ "Saves" ];
          writeDefault."cfg/a.cfg".text = "a";
          writeKeys."Engine.ini" = {
            format = "ini";
            content."Engine.Console".ConsoleKey = "F9";
          };
        };
        files.prefix.writeKeys."user.reg" = {
          format = "unityPrefs";
          content."Software/VRChat/VRChat".VRC_MIRROR_RESOLUTION = 3;
        };
      };
      apps.jellycar = {
        id = 1740930;
        compatTool = "proton_9";
        updateBehavior = "onLaunch";
        allowDownloadsWhileRunning = "never";
        rawLaunchOptions = "MANGOHUD=1 %command% -x";
      };
      nonSteamApps.probe = {
        target = "/opt/probe/run";
        inVrLibrary = true;
        overlay = false;
        env.SCN_APP = "probe";
      };
      nonSteamApps."Vintage Story".target = "/opt/vs/run";
    };
  };

  nixos =
    modules:
    (lib.nixosSystem {
      inherit system;
      modules = [
        self.nixosModules.default
        {
          nixpkgs.config.allowUnfree = true;
          system.stateVersion = "26.05";
          fileSystems."/" = {
            device = "none";
            fsType = "tmpfs";
          };
          boot.loader.grub.enable = false;
          programs.steam.enable = true;
          users.users.alice = {
            isNormalUser = true;
            uid = 1001;
          };
        }
      ]
      ++ modules;
    }).config;
  eval = nixos [ sample ];
  quoted = nixos [
    {
      programs.steam-config = {
        enable = true;
        apps."620" = {
          name = "Portal \"2\" $HOME `id`";
          systemd.enable = true;
          winetricks = [ "corefonts" ];
          preHook = "export Q=1";
        };
      };
    }
  ];
  mergedKeys = nixos [
    {
      programs.steam-config = {
        enable = true;
        apps."620".files.game.writeKeys."a.ini" = {
          format = "ini";
          content.S.a = 1;
        };
      };
    }
    { programs.steam-config.apps."620".files.game.writeKeys."a.ini".content.S.b = 2; }
  ];
  keepPath = import ../lib/keep-path.nix { inherit lib; };
  vintageEntry = lib.findFirst (
    p: lib.hasInfix "steam-config-nix-vintage-story" (p.name or "")
  ) (throw "no vintage story entry") eval.environment.systemPackages;

  cfg = eval.programs.steam-config;
  stateRule = lib.findFirst (
    r: lib.hasInfix "state.json" r
  ) (throw "no state rule") eval.systemd.tmpfiles.rules;
  stateFile = lib.last (lib.splitString " " stateRule);
  ruleTarget =
    prefix: rules:
    lib.last (
      lib.splitString " " (lib.findFirst (lib.hasPrefix prefix) (throw "no rule ${prefix}") rules)
    );
  launchTree = ruleTarget "L+ /var/lib/steam-config-nix/launch " eval.systemd.tmpfiles.rules;
  quotedLaunchTree = ruleTarget "L+ /var/lib/steam-config-nix/launch " quoted.systemd.tmpfiles.rules;
  launchShellTarget = ruleTarget "L+ /var/lib/steam-config-nix/launch-shell " eval.systemd.tmpfiles.rules;
  spec105600 = "${launchTree}/105600.json";
  specJellycar = "${launchTree}/1740930.json";
  specQuoted = "${quotedLaunchTree}/620.json";
  launch = self.packages.${system}.steam-config-launch;
  jq = lib.getExe pkgs.jq;
  bash = lib.getExe pkgs.bash;
  envRow =
    name: source:
    "  ${name}${lib.concatStrings (lib.genList (_: " ") (51 - lib.stringLength name))}${source}";
  filesSpec105600 = cfg.apps."105600".filesSpec;
  showApp = pkgs.writeText "show-105600" (
    lib.concatLines [
      "105600, app 105600"
      "  spec      @PWD@/xdg/steam-config-nix/launch/105600.json"
      "  global    @PWD@/xdg/steam-config-nix/launch/global.json"
      ""
      "environment, in the order applied"
      (envRow "PROTON_ENABLE_WAYLAND=1" "global")
      (envRow "SCN=x" "env")
      ""
      "scope"
      "  no user manager, launches without a scope"
      ""
      "files"
      "  ${filesSpec105600}"
      "  game      2 overlay, 1 hide, 1 passthrough, 1 writeDefault, 1 writeKeys"
      "  prefix    1 writeKeys"
      ""
      "command line"
      "  %command% -a 'two words'"
      ""
      "exec chain"
      "  ${lib.getExe launch} launch ${filesSpec105600} --"
      "  /bin/sh -c '%command% -a '\\''two words'\\'''"
    ]
  );

  expectedState = {
    onSteamRunning = "wait";
    steam = lib.getExe cfg.launcher;
    notifySend = lib.getExe' pkgs.libnotify "notify-send";
    globalCompatTool = "GE-Proton";
    libraryFolders = [ "/mnt/games" ];
    desktopUiScale = 1.25;
    apps = {
      "105600" = {
        overlay = false;
        steamInput = 2;
        libraryIcon = true;
        artwork.cover = "${art}";
      };
      "1740930" = {
        compatTool = "proton_9";
        updateBehavior = 1;
        backgroundDownloads = 2;
        libraryIcon = true;
      };
    };
    shortcuts."4132570534" = {
      name = "probe";
      exe = "/opt/probe/run";
      dir = "/opt/probe";
      vr = true;
      overlay = false;
    };
    shortcuts."3402148748" = {
      name = "Vintage Story";
      exe = "/opt/vs/run";
      dir = "/opt/vs";
    };
  };
  expectedJson = pkgs.writeText "expected-state.json" (lib.toJSON expectedState);

  layer = cfg.apps."105600".files.game.spec.layer;
  expectedSpec = {
    key = "105600";
    name = "105600";
    appId = 105600;
    bwrap = lib.getExe' pkgs.bubblewrap "bwrap";
    notifySend = lib.getExe' pkgs.libnotify "notify-send";
    locations = {
      game = {
        layer = "${layer}";
        overlay = [
          {
            target = "bin/tool";
            readOnly = true;
          }
          {
            target = "mods/x.txt";
            readOnly = false;
          }
        ];
        hide = [ "movies/intro.bik" ];
        passthrough = [ "Saves" ];
        writeDefault = [
          {
            target = "cfg/a.cfg";
            source = "${pkgs.writeText "steam-config-nix-file" "a"}";
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
      prefix = {
        layer = null;
        overlay = [ ];
        hide = [ ];
        passthrough = [ ];
        writeDefault = [ ];
        writeKeys = [
          {
            target = "user.reg";
            format = "unityPrefs";
            content."Software/VRChat/VRChat".VRC_MIRROR_RESOLUTION = 3;
            createIfMissing = false;
          }
        ];
      };
    };
  };
  expectedSpecJson = pkgs.writeText "expected-spec.json" (lib.toJSON expectedSpec);

  badFiles = {
    programs.steam.config.enable = true;
    programs.steam-config = {
      enable = true;
      package = pkgs.hello;
      nonSteamApps.probe = {
        target = "/opt/probe/run";
        allowOverlay = false;
        isHidden = true;
      };
      nonSteamApps."620".target = "/opt/b";
      nonSteamApps."!!!".target = "/opt/c";
      apps."620".env = {
        STEAM_LAUNCH_WRAPPER_SCOPE = "0";
        WINEDLLOVERRIDES = "winhttp=n,b";
      };
      apps."620".dllOverrides.winhttp = "n,b";
      apps."620".files.game = {
        overlay."Saves/x.txt".text = "x";
        overlay."a.cfg".text = "a";
        overlay."ro".source = art;
        overlay."ro".readOnly = true;
        overlay."nosource" = { };
        hide = [
          "../escape"
          "Saves/y"
        ];
        passthrough = [ "Saves" ];
        writeDefault."a.cfg".text = "b";
        writeKeys."ro/k.ini" = {
          format = "ini";
          content = { };
        };
        place."z".text = "z";
      };
    };
  };
  hmSteam = pkgs.writeShellScriptBin "steam" "";
  hmUser = {
    home.username = "alice";
    home.homeDirectory = "/home/alice";
    home.stateVersion = "26.05";
    programs.steam-config.steamPackage = hmSteam;
  };
  hm = (import "${home-manager}/lib" { inherit lib; }).homeManagerConfiguration {
    inherit pkgs;
    modules = [
      self.homeModules.default
      sample
      hmUser
      { home.packages = [ hmSteam ]; }
    ];
  };
  hmLayered = (import "${home-manager}/lib" { inherit lib; }).homeManagerConfiguration {
    inherit pkgs;
    modules = [
      self.homeModules.default
      hmUser
      {
        programs.steam-config = {
          enable = true;
          env.FROM_HM = 1;
          apps."105600".env.HM = "y";
          apps."440".overlay = true;
        };
      }
    ];
    extraSpecialArgs.osConfig = eval;
  };
  layeredHome = "${hmLayered.activationPackage}/home-files/.local/share/steam-config-nix";
  layeredCompatTool =
    value:
    ((import "${home-manager}/lib" { inherit lib; }).homeManagerConfiguration {
      inherit pkgs;
      modules = [
        self.homeModules.default
        hmUser
        {
          programs.steam-config = {
            enable = true;
            apps.jellycar.compatTool = value;
          };
        }
      ];
      extraSpecialArgs.osConfig = eval;
    }).config.programs.steam-config.apps.jellycar.compatTool;
  hmCfg = hm.config.programs.steam-config;
  hmStateFile = hm.config.home.file.".local/share/steam-config-nix/state.json".source;
  hmExpectedJson = pkgs.writeText "expected-hm-state.json" (
    lib.toJSON (lib.recursiveUpdate expectedState { steam = lib.getExe hmCfg.launcher; })
  );

  # homeManagerConfiguration throws on a failed assertion, so the bad config goes through the module set directly
  hmLib = import "${home-manager}/modules/lib/stdlib-extended.nix" lib;
  badMessages = map (a: a.message) (
    lib.filter (a: !a.assertion)
      (hmLib.evalModules {
        modules = [
          self.homeModules.default
          badFiles
          hmUser
        ]
        ++ import "${home-manager}/modules/modules.nix" {
          inherit pkgs;
          lib = hmLib;
        };
        class = "homeManager";
        specialArgs.modulesPath = "${home-manager}/modules";
      }).config.assertions
  );
  expectMessage =
    needle:
    lib.assertMsg (lib.any (m: lib.hasInfix needle m) badMessages) "missing assertion: ${needle}";
  patcherUnit = eval.systemd.user.services.steam-config-patcher;
  userActivation = pkgs.writeText "user-activation" eval.system.userActivationScripts.script;
in
{
  module-eval = pkgs.runCommand "module-eval" { } (
    assert lib.assertMsg (
      cfg.nonSteamApps.probe.id == 4132570534
      && cfg.nonSteamApps.probe.steamRunId == "17749255291976810496"
    ) "the shortcut id and run id follow the seed";
    assert lib.assertMsg (
      patcherUnit.serviceConfig.Type == "exec"
    ) "the patcher unit exits after a run so the next start runs it again";
    assert lib.assertMsg (
      cfg.nonSteamApps."Vintage Story".id == 3402148748
    ) "the seed is the attribute name";
    assert lib.assertMsg (
      eval.systemd.user.targets ? "steam-app-105600"
    ) "an app with systemd.enable gets a target";
    assert lib.assertMsg (
      mergedKeys.programs.steam-config.apps."620".files.game.writeKeys."a.ini".content == {
        S = {
          a = 1;
          b = 2;
        };
      }
    ) "writeKeys content merges across definitions";
    assert lib.assertMsg (
      let
        kept = keepPath ./default.nix;
      in
      lib.hasContext kept && lib.hasSuffix "-default.nix" kept
    ) "a path inside the store keeps a reference";
    assert lib.assertMsg (keepPath "/mnt/games" == "/mnt/games") "a string path is left alone";
    assert lib.assertMsg (
      !(eval.systemd.user.targets ? "steam-app-jellycar")
    ) "an app without systemd.enable gets no target";
    assert lib.assertMsg (
      quoted.programs.steam-config.apps."620".launchSpec.name == "Portal \"2\" $HOME `id` (620)"
    ) "the display name reaches the launch spec verbatim";
    assert lib.assertMsg (
      launchShellTarget == lib.getExe launch
    ) "the launch shell links the launch package";
    assert lib.assertMsg (lib.all (r: lib.elem r eval.systemd.tmpfiles.rules) [
      "r /var/lib/steam-config-nix/apps"
      "r /var/lib/steam-config-nix/launch-env.sh"
    ]) "the old dispatch link and launch env are cleaned up";
    assert lib.assertMsg (
      !(eval.system.activationScripts ? steam-config-nix-launch-shell)
    ) "the launch shell is a link, nothing is installed on activation";
    ''
      ${lib.getExe pkgs.jq} -S . ${stateFile} > actual.json
      ${lib.getExe pkgs.jq} -S . ${expectedJson} > expected.json
      diff expected.json actual.json
      ${lib.getExe pkgs.jq} -S . ${cfg.apps."105600".filesSpec} > actual-spec.json
      ${lib.getExe pkgs.jq} -S . ${expectedSpecJson} > expected-spec.json
      diff expected-spec.json actual-spec.json
      test "$(cat ${layer}/mods/x.txt)" = hi
      test -x ${layer}/bin/tool
      test ! -e ${layer}/movies
      test ! -e ${layer}/cfg
      grep -q 'steam://rungameid/14612117608820899840' ${vintageEntry}/share/applications/*.desktop
      ${jq} -e '.name == "Portal \"2\" $HOME `id` (620)"' ${specQuoted}
      grep -q 'STEAM_GAME_LAUNCH_SHELL=/var/lib/steam-config-nix/launch-shell' ${cfg.launcher}/bin/steam
      ${jq} -e '.env.SCN_APP == "probe" and .kind == "nonSteam"' ${launchTree}/4132570534.json
      ${jq} -e '.env.PROTON_ENABLE_WAYLAND == "1"' ${launchTree}/global.json
      test ! -e ${launchTree}/3402148748.json
      grep -q '/var/lib/steam-config-nix/state.json' ${patcherUnit.serviceConfig.ExecStart}
      grep -q 'local/share}/steam-config-nix"/state.json /var/lib' ${patcherUnit.serviceConfig.ExecStart}
      grep -q steam-config-patcher.service ${userActivation}
      touch $out
    ''
  );

  launch-shell = pkgs.runCommand "launch-shell" { } ''
    export HOME=$PWD
    data=$PWD/xdg/steam-config-nix
    mkdir -p $data
    touch $data/state.json
    ln -s ${launchShellTarget} $data/launch-shell
    ln -s ${launchTree} $data/launch
    export XDG_DATA_HOME=$PWD/xdg
    shell=$data/launch-shell
    expect() {
      test "$1" = "$2" || { echo "expected: $2, got: $1"; exit 1; }
    }

    export SteamAppId=105600
    expect "$($shell "printf '[%s]' x" 2>err)" "[x][-a][two words]"
    grep -q 'game: not found, its files are skipped' err
    grep -q 'No systemd user manager' err
    expect "$($shell -c "printf '[%s]' x" 2>/dev/null)" "[x][-a][two words]"

    export SteamAppId=1740930
    expect "$($shell "printf '[%s]' x")" "[x][-x]"
    expect "$($shell "sh -c 'printf %s \"\$MANGOHUD\"'")" 1

    export SteamAppId=440
    expect "$($shell 'echo "$PROTON_ENABLE_WAYLAND"')" 1
    expect "$($shell 'echo game' extra)" game

    export SteamAppId=4132570534
    expect "$($shell 'echo "$SCN_APP"')" probe

    alt=$PWD/alt/steam-config-nix
    mkdir -p $alt/launch $PWD/prefixes
    touch $alt/state.json
    ln -s ${launchShellTarget} $alt/launch-shell
    export XDG_DATA_HOME=$PWD/alt
    shell=$alt/launch-shell
    spec() {
      ${jq} -n --argjson id "$1" "{version: 1, key: \"t\", appId: \$id, kind: \"steam\", name: \"t\", notifySend: null, env: {}, dllOverrides: {}, args: [], wrappers: []} + $2" > $alt/launch/$1.json
    }

    export SteamAppId=440
    echo garbage > $alt/launch/global.json
    expect "$($shell 'echo game' 2>err)" game
    grep -q global.json err
    rm $alt/launch/global.json
    expect "$($shell 'echo game')" game

    export SteamAppId=7
    echo '{"version": 2}' > $alt/launch/7.json
    expect "$($shell 'echo game' 2>err)" game
    grep -q 7.json err

    spec 7 '{prefixPath: "'$PWD'/missing/7"}'
    if $shell 'touch ran' 2>err; then exit 1; else expect $? 1; fi
    test ! -e ran
    grep -q 'refusing to create it' err
    spec 7 '{prefixPath: "'$PWD'/prefixes/7"}'
    expect "$($shell 'echo "$STEAM_COMPAT_DATA_PATH"')" $PWD/prefixes/7
    test -d prefixes/7


    spec 7 '{wrappers: ["A=1", "sh", "-c", "exec \"$@\"", "w"], envProgram: "${lib.getExe' pkgs.coreutils "env"}"}'
    expect "$($shell 'echo "$A"')" 1

    spec 7 '{preHook: "export HOOK=1\ncmdline=\"printf %s- edited $HOOK\"\nargs+=(\"two words\")", shell: "${bash}", args: ["-a"]}'
    expect "$($shell 'printf x')" "edited-1--a-two words-"

    spec 7 '{env: {DROP: null, KEEP: "k"}, dllOverrides: {d3d9: "disabled", winhttp: "n,b"}}'
    expect "$(DROP=1 WINEDLLOVERRIDES=old $shell 'echo "''${DROP-unset} $KEEP $WINEDLLOVERRIDES"')" "unset k d3d9=;winhttp=n,b"

    spec 7 '{steamScope: false}'
    expect "$($shell 'echo "$STEAM_LAUNCH_WRAPPER_SCOPE"')" 0
    spec 7 '{scope: {systemdRun: "/nonexistent", systemctl: "${lib.getExe' pkgs.coreutils "false"}", properties: {}}}'
    expect "$(STEAM_LAUNCH_WRAPPER_SCOPE=1 $shell 'echo "$STEAM_LAUNCH_WRAPPER_SCOPE"' 2>err)" 1
    grep -q 'No systemd user manager, launching t without a scope' err

    printf '#!%s\necho "$*" >> %s/pt.log\nexit "''${PT_EXIT:-0}"\n' ${bash} "$PWD" > pt
    chmod +x pt
    spec 7 '{winetricks: {verbs: ["a", "b"], protontricks: "'$PWD'/pt", bwrap: null}}'
    export STEAM_COMPAT_DATA_PATH=$PWD/compat STEAM_COMPAT_APP_ID=7
    expect "$($shell 'echo game')" game
    test ! -e pt.log
    mkdir -p compat/pfx
    PT_EXIT=1 $shell 'echo game' > out 2>err
    expect "$(tail -n1 out)" game
    grep -qx 'steam-config-nix: applying winetricks verbs: a b' out
    grep -q 'winetricks failed (exit status: 1), continuing to launch' err
    test ! -e compat/steam-config-nix-winetricks
    $shell 'echo game' > out
    expect "$(tail -n1 out)" game
    expect "$(cat compat/steam-config-nix-winetricks)" "a b"
    expect "$($shell 'echo game')" game
    expect "$(wc -l < pt.log)" 2
    grep -qx '7 -q a b' pt.log
    unset STEAM_COMPAT_DATA_PATH STEAM_COMPAT_APP_ID

    if $shell 2>/dev/null; then exit 1; else expect $? 2; fi

    export XDG_DATA_HOME=$PWD/xdg
    show() { ${lib.getExe launch} show "$@" | sed "s|$PWD|@PWD@|g"; }
    show 105600 | diff ${showApp} -
    if ${lib.getExe launch} show nosuch 2>/dev/null; then exit 1; else expect $? 1; fi

    touch $out
  '';

  launch-spec = pkgs.runCommand "launch-spec" { } ''
    ${jq} -e '.env.SCN == "x" and .args == ["-a", "two words"]' ${spec105600}
    ${jq} -e '.shell == null and .envProgram == null and .steamScope == null' ${spec105600}
    ${jq} -e '.scope.properties | .Description == "105600" and .Wants == "steam-app-105600.target" and .After == "steam-app-105600.target"' ${spec105600}
    ${jq} -e '.files == "${cfg.apps."105600".filesSpec}"' ${spec105600}
    ${jq} -e '.rawLaunchOptions == "MANGOHUD=1 %command% -x" and .files == null and .scope == null' ${specJellycar}
    ${jq} -e '.winetricks.verbs == ["corefonts"] and .winetricks.bwrap == null' ${specQuoted}
    ${jq} -e '.notifySend | startswith("/nix/store/")' ${specQuoted}
    ${jq} -e '.wrappers == [] and .envProgram == "${lib.getExe' pkgs.coreutils "env"}"' ${specQuoted}
    touch $out
  '';

  home-manager = pkgs.runCommand "home-manager" { } (
    assert lib.assertMsg (
      hm.config.systemd.user.targets ? "steam-app-105600"
    ) "an app with systemd.enable gets a target";
    assert lib.assertMsg (
      hm.config.xdg.desktopEntries ? "steam-config-nix-105600"
    ) "a configured app gets a desktop entry";
    assert lib.assertMsg (
      hm.config.home.activation ? steam-config-nix-patcher
    ) "the activation starts the patcher";
    ''
      grep -q '/home/alice/.local/share/steam-config-nix/state.json' ${toString hm.config.systemd.user.services.steam-config-patcher.Service.ExecStart}
      ${lib.getExe pkgs.jq} -S . ${hmStateFile} > actual.json
      ${lib.getExe pkgs.jq} -S . ${hmExpectedJson} > expected.json
      diff expected.json actual.json
      home=${hm.activationPackage}/home-files
      test -f $home/.local/share/steam-config-nix/state.json
      for id in 105600 1740930 4132570534 global; do
        test -f $home/.local/share/steam-config-nix/launch/$id.json
      done
      test ! -e $home/.local/share/steam-config-nix/apps
      test "$(readlink -f $home/.local/share/steam-config-nix/launch-shell)" = ${lib.getExe launch}
      grep -q 'STEAM_GAME_LAUNCH_SHELL=/home/alice/.local/share/steam-config-nix/launch-shell' ${hm.activationPackage}/home-path/bin/steam
      grep -q 'Icon=steam-config-nix-105600' ${hm.activationPackage}/home-path/share/applications/steam-config-nix-105600.desktop
      touch $out
    ''
  );

  layered = pkgs.runCommand "layered" { } (
    assert lib.assertMsg (
      !(hmLayered.config.home.file ? ".local/share/steam-config-nix/launch-shell")
    ) "the NixOS launch shell serves a layered Home Manager user";
    assert lib.assertMsg (
      !(lib.tryEval (layeredCompatTool "proton_experimental")).success
    ) "a value set differently on both sides is a conflict";
    assert lib.assertMsg (
      layeredCompatTool (lib.mkForce "proton_experimental") == "proton_experimental"
    ) "mkForce on the Home Manager side settles a conflict";
    assert lib.assertMsg (
      !(hmLayered.config.systemd.user.services ? steam-config-patcher)
    ) "the NixOS patcher unit serves a layered Home Manager user";
    assert lib.assertMsg (
      hmLayered.config.home.activation ? steam-config-nix-patcher
    ) "a layered Home Manager user still starts the patcher on activation";
    ''
      ${lib.getExe pkgs.jq} -e '.apps | has("105600") and has("1740930") and has("440")' ${layeredHome}/state.json
      ${lib.getExe pkgs.jq} -e '.shortcuts | has("4132570534")' ${layeredHome}/state.json
      ${lib.getExe pkgs.jq} -e '.shortcuts."4132570534".exe == "/opt/probe/run" and .globalCompatTool == "GE-Proton"' ${layeredHome}/state.json
      ${jq} -e '.env.SCN == "x" and .env.HM == "y"' ${layeredHome}/launch/105600.json
      ${jq} -e '.env.PROTON_ENABLE_WAYLAND == "1" and .env.FROM_HM == "1"' ${layeredHome}/launch/global.json
      grep -q 'STEAM_GAME_LAUNCH_SHELL=/var/lib/steam-config-nix/launch-shell' ${hmLayered.config.programs.steam-config.launcher}/bin/steam
      touch $out
    ''
  );

  inherit launch;
  patcher = self.packages.${system}.steam-config-patcher;
  files-vm = import ./files-vm.nix { inherit self pkgs system; };
  patcher-vm = import ./patcher-vm.nix { inherit self pkgs system; };

  files-assertions = pkgs.runCommand "files-assertions" { } (
    assert expectMessage "`Saves/x.txt` is served by `overlay` but `Saves` is in `passthrough`";
    assert expectMessage "`Saves/y` is in `hide` but `Saves` is in `passthrough`";
    assert expectMessage "`a.cfg` is declared under both `overlay` and `writeDefault`";
    assert expectMessage "`../escape` must be a relative path inside the game";
    assert expectMessage "`ro/k.ini` is written under `ro`, which is `readOnly`";
    assert expectMessage "`overlay.nosource` needs exactly one of `source` or `text`";
    assert expectMessage "`place` was renamed";
    assert expectMessage "`allowOverlay` was renamed to `overlay`";
    assert expectMessage "`isHidden` was renamed to `hidden`";
    assert expectMessage "programs.steam.config was renamed to programs.steam-config";
    assert expectMessage "`env.STEAM_LAUNCH_WRAPPER_SCOPE` conflicts with `systemd.steamScope`";
    assert expectMessage "`env.WINEDLLOVERRIDES` is replaced by `dllOverrides`";
    assert expectMessage "more than one app has the key 620.";
    assert expectMessage "needs at least one letter or digit in a-z0-9: !!!";
    assert expectMessage "`package` was split into `packages.patcher` and `packages.launch`";
    "touch $out"
  );

  formatting = pkgs.runCommand "formatting" { nativeBuildInputs = [ self.formatter.${system} ]; } ''
    cp -r ${self} src
    chmod -R u+w src
    cd src
    treefmt --ci --no-cache --tree-root "$PWD"
    touch $out
  '';
}
