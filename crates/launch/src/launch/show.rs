use std::ffi::OsString;
use std::fmt::Write;
use std::path::{Path, PathBuf};

use super::cmdline::{self, quote};
use super::env::EnvPlan;
use super::spec::{self, GlobalSpec, Kind, LaunchSpec};
use super::{COMPAT_DATA, apply_spec_env, chain, prefix, scope, winetricks};

pub struct Global<'a> {
    pub path: &'a Path,
    pub spec: Result<Option<GlobalSpec>, String>,
}

pub struct View<'a> {
    pub exe: &'a Path,
    pub spec_path: &'a Path,
    pub spec: &'a LaunchSpec,
    pub global: Global<'a>,
    pub cmdline: &'a str,
    pub probe: bool,
    pub pid: &'a str,
}

fn row(out: &mut String, label: &str, value: impl std::fmt::Display) {
    let _ = writeln!(out, "  {label:<9} {value}");
}

fn global_rows(out: &mut String, global: &Global, plan: &mut EnvPlan) {
    match &global.spec {
        Ok(Some(g)) => {
            row(out, "global", global.path.display());
            plan.extend(&g.env, "global");
        }
        Ok(None) => {}
        Err(e) => row(out, "global", format!("{e}, ignored")),
    }
}

fn env_section(out: &mut String, plan: &EnvPlan) {
    if plan.entries.is_empty() {
        return;
    }
    out.push_str("\nenvironment, in the order applied\n");
    for e in &plan.entries {
        let name = e.name.to_string_lossy();
        let (left, source) = match &e.value {
            Some(v) => (
                format!("{name}={}", v.to_string_lossy()),
                e.source.to_string(),
            ),
            None => (name.into_owned(), format!("{}, unset", e.source)),
        };
        let _ = writeln!(out, "  {left:<50} {source}");
    }
}

fn winetricks_state(compat: Option<&OsString>, want: &str) -> String {
    let Some(compat) = compat.filter(|c| !c.is_empty()).map(Path::new) else {
        return "waits for the prefix to be created".into();
    };
    if !compat.join("pfx").is_dir() {
        return "waits for the prefix to be created".into();
    }
    match winetricks::read_marker(&compat.join(winetricks::MARKER)) {
        Some(m) if m == want => "installed".into(),
        Some(m) => format!("pending, the prefix has \"{m}\""),
        None => "pending, no marker".into(),
    }
}

fn files_section(out: &mut String, path: &Path) {
    out.push_str("\nfiles\n");
    let _ = writeln!(out, "  {}", path.display());
    let files = match crate::spec::load(path) {
        Ok(files) => files,
        Err(e) => {
            let _ = writeln!(out, "  {e}");
            return;
        }
    };
    for (name, loc) in &files.locations {
        let counts = [
            (loc.overlay.len(), "overlay"),
            (loc.hide.len(), "hide"),
            (loc.passthrough.len(), "passthrough"),
            (loc.write_default.len(), "writeDefault"),
            (loc.write_keys.len(), "writeKeys"),
        ];
        let parts: Vec<String> = counts
            .iter()
            .filter(|(n, _)| *n > 0)
            .map(|(n, what)| format!("{n} {what}"))
            .collect();
        if !parts.is_empty() {
            row(out, name, parts.join(", "));
        }
    }
}

pub fn render(view: View) -> String {
    let spec = view.spec;
    let mut out = String::new();
    let kind = match spec.kind {
        Kind::Steam => "app",
        Kind::NonSteam => "non-Steam app",
    };
    let _ = writeln!(out, "{}, {kind} {}", spec.name, spec.app_id);
    row(&mut out, "spec", view.spec_path.display());
    let mut plan = EnvPlan::with_base(Vec::new());
    global_rows(&mut out, &view.global, &mut plan);

    apply_spec_env(&mut plan, spec);
    if let Some(p) = &spec.prefix_path {
        plan.set(COMPAT_DATA, p, "prefixPath");
    }
    let head = spec
        .scope
        .as_ref()
        .filter(|_| view.probe)
        .map(|s| scope::head(s, &scope::unit(spec.app_id, view.pid)));
    if head.is_some() {
        scope::steam_off(&mut plan);
    }
    env_section(&mut out, &plan);

    if let Some(p) = &spec.prefix_path {
        let parent = prefix::parent_of(p);
        let state = if p.is_dir() {
            "exists".to_string()
        } else if parent.is_dir() {
            "parent exists".to_string()
        } else {
            format!(
                "parent {} is missing, the launch is refused",
                parent.display()
            )
        };
        let _ = write!(out, "\nprefix\n  {}, {state}\n", p.display());
    }

    if let Some(w) = &spec.winetricks {
        let want = winetricks::want(w);
        let state = if plan.entries.iter().any(|e| e.name == COMPAT_DATA) {
            winetricks_state(plan.get(COMPAT_DATA).as_ref(), &want)
        } else {
            match crate::roots::compat_data(spec.app_id) {
                Some(dir) => winetricks_state(Some(&dir.into_os_string()), &want),
                None => "prefix chosen by Steam at launch, state unknown".into(),
            }
        };
        let _ = write!(out, "\nwinetricks\n  {want}\n  {state}\n");
    }

    if let Some(s) = &spec.scope {
        out.push_str("\nscope\n");
        if view.probe {
            let _ = writeln!(
                out,
                "  {}, user manager reachable",
                scope::unit(spec.app_id, view.pid)
            );
            for (k, v) in &s.properties {
                let _ = writeln!(out, "  {k}={v}");
            }
        } else {
            out.push_str("  no user manager, launches without a scope\n");
        }
    }

    if let Some(files) = &spec.files {
        files_section(&mut out, files);
    }

    if let Some(hook) = &spec.pre_hook {
        out.push_str("\npreHook\n");
        for line in hook.lines() {
            let _ = writeln!(out, "  {line}");
        }
        out.push_str("  runs before everything below and may change the command line, wrappers, args and environment\n");
    }

    let command = cmdline::build(view.cmdline, spec.raw_launch_options.as_deref(), &spec.args);
    let _ = write!(out, "\ncommand line\n  {command}\n");

    let links = chain::links(chain::Links {
        scope_head: head,
        self_exe: view.exe,
        files: spec.files.as_deref(),
        env_program: spec.env_program.as_deref(),
        wrappers: &spec.wrappers,
        cmdline: &command,
    });
    out.push_str("\nexec chain\n");
    for link in links {
        let quoted: Vec<String> = link.iter().map(|a| quote(&a.to_string_lossy())).collect();
        let _ = writeln!(out, "  {}", quoted.join(" "));
    }
    out
}

pub fn render_unconfigured(app: &str, global: Global) -> String {
    let mut out = format!("app {app} has no settings, it launches with the global env\n");
    let mut plan = EnvPlan::default();
    global_rows(&mut out, &global, &mut plan);
    env_section(&mut out, &plan);
    out
}

fn slugify(s: &str) -> String {
    let mapped: String = s
        .to_lowercase()
        .chars()
        .map(|c| match c {
            'a'..='z' | '0'..='9' => c,
            _ => '-',
        })
        .collect();
    mapped
        .split('-')
        .filter(|p| !p.is_empty())
        .collect::<Vec<_>>()
        .join("-")
}

fn find(dir: &Path, app: &str) -> Option<PathBuf> {
    if app.parse::<u64>().is_ok() {
        let path = dir.join(format!("{app}.json"));
        if path.exists() {
            return Some(path);
        }
    }
    let mut entries: Vec<PathBuf> = std::fs::read_dir(dir)
        .ok()?
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.extension().is_some_and(|x| x == "json") && !p.ends_with("global.json"))
        .collect();
    entries.sort();
    let slug = slugify(app);
    entries.into_iter().find(|p| {
        spec::load_app(p)
            .ok()
            .flatten()
            .is_some_and(|s| s.key == app || s.key == slug)
    })
}

fn usage() -> ! {
    eprintln!("usage: steam-config-launch show <app id or attribute name> [-- <command line>]");
    std::process::exit(2);
}

pub fn main(args: &[OsString]) -> ! {
    let Some((app, rest)) = args.split_first() else {
        usage()
    };
    let Some(app) = app.to_str() else { usage() };
    let cmdline = match rest.split_first() {
        None => "%command%".to_string(),
        Some((sep, cmd)) if sep == "--" && !cmd.is_empty() => cmd
            .iter()
            .map(|a| a.to_string_lossy())
            .collect::<Vec<_>>()
            .join(" "),
        _ => usage(),
    };
    let data = spec::current_data_dir();
    let dir = data.join("launch");
    let exe =
        std::fs::canonicalize(data.join("launch-shell")).unwrap_or_else(|_| super::self_exe());
    let global_path = dir.join("global.json");
    let global = Global {
        path: &global_path,
        spec: spec::load_global(&global_path),
    };
    let Some(spec_path) = find(&dir, app) else {
        if app.parse::<u64>().is_ok() {
            print!("{}", render_unconfigured(app, global));
            std::process::exit(0);
        }
        eprintln!("steam-config-nix: no app {app} in {}", dir.display());
        std::process::exit(1);
    };
    let spec = match spec::load_app(&spec_path) {
        Ok(Some(spec)) => spec,
        Ok(None) => {
            eprintln!("steam-config-nix: no app {app} in {}", dir.display());
            std::process::exit(1);
        }
        Err(e) => {
            eprintln!("steam-config-nix: {e}");
            std::process::exit(1);
        }
    };
    let probe = spec
        .scope
        .as_ref()
        .is_some_and(|s| scope::probe(s, &EnvPlan::default()));
    print!(
        "{}",
        render(View {
            exe: &exe,
            spec_path: &spec_path,
            spec: &spec,
            global,
            cmdline: &cmdline,
            probe,
            pid: "<pid>",
        })
    );
    std::process::exit(0);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::launch::spec::tests::{PORTAL, PROBE, temp};
    use std::fs;

    const FILES: &str = r#"{"key":"620","name":"Portal 2 (portal)","appId":620,"bwrap":"/b/bwrap","notifySend":null,"locations":{
  "game":{"overlay":[{"target":"a"},{"target":"b"}],"hide":["c"],"passthrough":["d"],
          "writeDefault":[{"target":"e","source":"/s/e"}],"writeKeys":[{"target":"f","format":"ini","content":{}}]},
  "prefix":{"writeKeys":[{"target":"g","format":"registry","content":{}}]}}}"#;

    const GOLDEN: &str = r#"Portal 2 (portal), app 620
  spec      /data/launch/620.json
  global    /data/launch/global.json

environment, in the order applied
  PROTON_ENABLE_WAYLAND=1                            global
  DXVK_HUD=fps                                       env
  PROTON_LOG=1                                       env
  TZ                                                 env, unset
  WINEDLLOVERRIDES=d3d9=;winhttp=n,b                 dllOverrides
  STEAM_COMPAT_DATA_PATH=/mnt/prefixes/620           prefixPath
  STEAM_LAUNCH_WRAPPER_SCOPE=0                       systemd

prefix
  /mnt/prefixes/620, exists

winetricks
  corefonts vcrun2022
  pending, the prefix has "corefonts"

scope
  app-steam-620-<pid>.scope, user manager reachable
  After=steam-app-portal-2.target
  CPUWeight=150
  Description=Portal 2 (portal)
  Slice=games.slice
  Wants=steam-app-portal-2.target

files
  /mnt/files-620.json
  game      2 overlay, 1 hide, 1 passthrough, 1 writeDefault, 1 writeKeys
  prefix    1 writeKeys

preHook
  export START=$(date +%s)
  runs before everything below and may change the command line, wrappers, args and environment

command line
  X=1 %command% -r -a 'two words'

exec chain
  /nix/store/x-systemd/bin/systemd-run --user --scope --quiet --collect --expand-environment=no '--unit=app-steam-620-<pid>.scope' --property=After=steam-app-portal-2.target --property=CPUWeight=150 '--property=Description=Portal 2 (portal)' --property=Slice=games.slice --property=Wants=steam-app-portal-2.target --
  /data/launch-shell launch /mnt/files-620.json --
  /nix/store/x-coreutils/bin/env -- /nix/store/x-gamescope/bin/gamescope -f --
  /bin/sh -c 'X=1 %command% -r -a '\''two words'\'''
"#;

    fn global() -> Result<Option<GlobalSpec>, String> {
        spec::parse_global(r#"{"version":1,"notifySend":null,"env":{"PROTON_ENABLE_WAYLAND":"1"}}"#)
            .map(Some)
    }

    #[test]
    fn golden_620() {
        let root = temp("show");
        let tmp = root.to_str().unwrap();
        let pfx = root.join("prefixes/620");
        fs::create_dir_all(pfx.join("pfx")).unwrap();
        fs::write(pfx.join(winetricks::MARKER), "corefonts\n").unwrap();
        fs::write(root.join("files-620.json"), FILES).unwrap();
        let text = PORTAL.replace("/mnt/games", tmp).replace(
            "/nix/store/x-steam-config-nix-files-620.json",
            &format!("{tmp}/files-620.json"),
        );
        let spec = spec::parse_app(&text).unwrap();
        let out = render(View {
            exe: Path::new("/data/launch-shell"),
            spec_path: Path::new("/data/launch/620.json"),
            spec: &spec,
            global: Global {
                path: Path::new("/data/launch/global.json"),
                spec: global(),
            },
            cmdline: "%command%",
            probe: true,
            pid: "<pid>",
        });
        let out: String = out
            .replace(tmp, "/mnt")
            .lines()
            .map(|l| match l.strip_prefix("  STEAM_COMPAT_DATA_PATH=") {
                Some(rest) => {
                    let (value, source) = rest.rsplit_once(' ').unwrap();
                    format!(
                        "  {:<50} {source}\n",
                        format!("STEAM_COMPAT_DATA_PATH={}", value.trim())
                    )
                }
                None => format!("{l}\n"),
            })
            .collect();
        assert_eq!(out, GOLDEN);
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn no_manager() {
        let spec = spec::parse_app(PORTAL).unwrap();
        let out = render(View {
            exe: Path::new("/data/launch-shell"),
            spec_path: Path::new("/data/launch/620.json"),
            spec: &spec,
            global: Global {
                path: Path::new("/data/launch/global.json"),
                spec: Ok(None),
            },
            cmdline: "game",
            probe: false,
            pid: "<pid>",
        });
        assert!(out.contains("no user manager, launches without a scope"));
        assert!(!out.contains("STEAM_LAUNCH_WRAPPER_SCOPE"));
        assert!(!out.contains("systemd-run"));
        assert!(!out.contains("  global "));
        assert!(out.contains("command line\n  X=1 game -r -a 'two words'\n"));
    }

    #[test]
    fn unconfigured() {
        let out = render_unconfigured(
            "440",
            Global {
                path: Path::new("/data/launch/global.json"),
                spec: global(),
            },
        );
        assert_eq!(
            out,
            format!(
                "app 440 has no settings, it launches with the global env\n  global    /data/launch/global.json\n\nenvironment, in the order applied\n  {:<50} global\n",
                "PROTON_ENABLE_WAYLAND=1"
            )
        );
    }

    #[test]
    fn lookup_by_key() {
        let dir = temp("show-find");
        fs::write(dir.join("4132570534.json"), PROBE).unwrap();
        fs::write(dir.join("620.json"), PORTAL).unwrap();
        fs::write(dir.join("global.json"), "{}").unwrap();
        assert_eq!(find(&dir, "probe"), Some(dir.join("4132570534.json")));
        assert_eq!(find(&dir, "Probe!"), Some(dir.join("4132570534.json")));
        assert_eq!(slugify("My  Probe (2)"), "my-probe-2");
        let probe = spec::parse_app(PROBE).unwrap();
        let out = render(View {
            exe: Path::new("/data/launch-shell"),
            spec_path: &dir.join("4132570534.json"),
            spec: &probe,
            global: Global {
                path: Path::new("/data/launch/global.json"),
                spec: Ok(None),
            },
            cmdline: "%command%",
            probe: false,
            pid: "<pid>",
        });
        assert!(out.starts_with("probe, non-Steam app 4132570534\n"));
        assert!(out.contains("command line\n  %command% --verbose\n"));
        assert_eq!(find(&dir, "620"), Some(dir.join("620.json")));
        assert_eq!(find(&dir, "nosuch"), None);
        assert_eq!(find(&dir, "440"), None);
        let _ = fs::remove_dir_all(&dir);
    }
}
