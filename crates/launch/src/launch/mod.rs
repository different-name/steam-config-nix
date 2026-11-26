pub mod chain;
pub mod cmdline;
pub mod env;
pub mod prefix;
pub mod prehook;
pub mod scope;
pub mod show;
pub mod spec;
pub mod winetricks;

use std::ffi::{OsStr, OsString};
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::Command;

use crate::notify::{log, notify_in};
use env::EnvPlan;
use spec::LaunchSpec;

pub const COMPAT_DATA: &str = "STEAM_COMPAT_DATA_PATH";

#[derive(Debug, PartialEq)]
pub enum Mode {
    Launch(Vec<OsString>),
    Inner(Vec<OsString>),
    Show(Vec<OsString>),
    Shell(OsString),
    Usage,
}

pub fn dispatch(argv0: &OsStr, args: &[OsString], steam_app_id: bool) -> Mode {
    let rest = || args[1..].to_vec();
    match args.first().and_then(|a| a.to_str()) {
        Some("launch") => return Mode::Launch(rest()),
        Some("inner") => return Mode::Inner(rest()),
        Some("show") => return Mode::Show(rest()),
        _ => {}
    }
    let shell_name = Path::new(argv0).file_name() == Some(OsStr::new("launch-shell"));
    if !shell_name && !steam_app_id {
        return Mode::Usage;
    }
    let args = match args.first() {
        Some(first) if first == "-c" => &args[1..],
        _ => args,
    };
    match args.first() {
        Some(cmdline) => Mode::Shell(cmdline.clone()),
        None => Mode::Usage,
    }
}

fn exec(argv: Vec<OsString>, plan: &EnvPlan) -> ! {
    let mut cmd = Command::new(&argv[0]);
    cmd.args(&argv[1..]);
    let err = plan.apply(&mut cmd).exec();
    log(format!("{}: {err}", argv[0].to_string_lossy()));
    std::process::exit(127);
}

fn plain(cmdline: &str, plan: &EnvPlan) -> ! {
    exec(vec!["/bin/sh".into(), "-c".into(), cmdline.into()], plan)
}

pub(crate) fn self_exe() -> PathBuf {
    std::env::current_exe()
        .map(spec::strip_deleted)
        .unwrap_or_else(|_| PathBuf::from("/proc/self/exe"))
}

pub fn shell(cmdline: OsString) -> ! {
    let cmdline = cmdline
        .into_string()
        .unwrap_or_else(|s| s.to_string_lossy().into_owned());
    let app_id = std::env::var("SteamAppId").ok().filter(|v| !v.is_empty());
    let dir = spec::current_data_dir().join("launch");
    let mut plan = EnvPlan::default();

    let global = match spec::load_global(&dir.join("global.json")) {
        Ok(global) => global,
        Err(e) => {
            log(format!("{e}, launching without the global env"));
            None
        }
    };
    let global_notify = global.as_ref().and_then(|g| g.notify_send.clone());
    if let Some(global) = &global {
        plan.extend(&global.env, "global");
    }

    let Some(app_id) = app_id else {
        plain(&cmdline, &plan)
    };
    match spec::load_app(&dir.join(format!("{app_id}.json"))) {
        Ok(Some(spec)) => run(spec, plan, cmdline),
        Ok(None) => plain(&cmdline, &plan),
        Err(e) => {
            let msg = format!("{e}, launched without its settings");
            log(&msg);
            notify_in(global_notify.as_deref(), &msg, Some(&plan));
            plain(&cmdline, &plan)
        }
    }
}

pub fn apply_spec_env(plan: &mut EnvPlan, spec: &LaunchSpec) {
    plan.extend(&spec.env, "env");
    if let Some(dlls) = env::dll_overrides(&spec.dll_overrides) {
        plan.set("WINEDLLOVERRIDES", dlls, "dllOverrides");
    }
}

fn run_winetricks(spec: &LaunchSpec, plan: &EnvPlan, orig: Option<OsString>) {
    let Some(tricks) = &spec.winetricks else {
        return;
    };
    let notify = |body: &str| notify_in(spec.notify_send.as_deref(), body, Some(plan));
    let compat = plan.get(COMPAT_DATA);
    let app_id = plan.get("STEAM_COMPAT_APP_ID");
    let decision = winetricks::decide(
        tricks,
        &winetricks::Inputs {
            compat: compat.as_deref(),
            orig: orig.as_deref(),
            prefix_path: spec.prefix_path.is_some(),
            app_id: app_id.as_deref(),
        },
    );
    let (want, marker, argv) = match decision {
        winetricks::Decision::Skip | winetricks::Decision::Installed => return,
        winetricks::Decision::SkipLogged(msg) => return log(msg),
        winetricks::Decision::Run {
            want, marker, argv, ..
        } => (want, marker, argv),
    };
    println!("steam-config-nix: applying winetricks verbs: {want}");
    notify(&format!("Installing winetricks: {want}..."));
    let mut cmd = Command::new(&argv[0]);
    cmd.args(&argv[1..]);
    match plan.apply(&mut cmd).status() {
        Ok(status) if status.success() => {
            if let Err(e) = std::fs::write(&marker, &want) {
                log(format!("{}: {e}", marker.display()));
            }
            notify(&format!("winetricks installed: {want}"));
        }
        Ok(status) => {
            log(format!(
                "winetricks failed ({status}), continuing to launch"
            ));
            notify(&format!("winetricks failed for {}", spec.name));
        }
        Err(e) => {
            log(format!(
                "{}: {e}, winetricks failed, continuing to launch",
                argv[0].to_string_lossy()
            ));
            notify(&format!("winetricks failed for {}", spec.name));
        }
    }
}

fn run(spec: LaunchSpec, mut plan: EnvPlan, cmdline: String) -> ! {
    let notify_send = spec.notify_send.as_deref();
    apply_spec_env(&mut plan, &spec);

    let orig = (spec.prefix_path.is_some() && spec.winetricks.is_some())
        .then(|| plan.get(COMPAT_DATA))
        .flatten();
    if let Some(prefix) = &spec.prefix_path {
        if let Err(refused) = prefix::prepare(prefix) {
            log(refused.log_line());
            notify_in(notify_send, &refused.notification(), Some(&plan));
            std::process::exit(1);
        }
        plan.set(COMPAT_DATA, prefix, "prefixPath");
    }
    run_winetricks(&spec, &plan, orig);

    let mut state = prehook::State {
        cmdline,
        wrappers: spec.wrappers.clone(),
        args: spec.args.clone(),
    };
    if let Some(hook) = &spec.pre_hook {
        let shell = spec.shell.as_deref().unwrap_or(Path::new("bash"));
        match prehook::run(shell, hook, &state, &plan) {
            Ok(prehook::Outcome::Continue(edited, env, process)) => {
                state = edited;
                plan = EnvPlan::with_base(env);
                prehook::apply_process(&process);
            }
            Ok(prehook::Outcome::Exited(code)) => {
                log(format!(
                    "preHook exited with {code}, {} not launched",
                    spec.name
                ));
                if code != 0 {
                    notify_in(
                        notify_send,
                        &format!("preHook for {} exited with {code}, not launched", spec.name),
                        Some(&plan),
                    );
                }
                std::process::exit(code);
            }
            Err(e) => {
                log(format!("{e}, {} not launched", spec.name));
                notify_in(
                    notify_send,
                    &format!("preHook for {} failed, not launched", spec.name),
                    Some(&plan),
                );
                std::process::exit(127);
            }
        }
    }

    let command = cmdline::build(
        &state.cmdline,
        spec.raw_launch_options.as_deref(),
        &state.args,
    );

    let mut head = None;
    let mut parts = Vec::new();
    if let Some(s) = &spec.scope {
        if scope::probe(s, &plan) {
            let unit = scope::unit(spec.app_id, std::process::id());
            head = Some(scope::head(s, &unit));
            parts.push(format!("scope {unit}"));
        } else {
            let msg = format!(
                "No systemd user manager, launching {} without a scope",
                spec.name
            );
            log(&msg);
            notify_in(notify_send, &msg, Some(&plan));
        }
    }
    if head.is_some() {
        scope::steam_off(&mut plan);
    }
    if spec.pre_hook.is_some() {
        parts.push("preHook".into());
    }
    if spec.files.is_some() {
        parts.push("files".into());
    }

    let exe = self_exe();
    let links = chain::links(chain::Links {
        scope_head: head,
        self_exe: &exe,
        files: spec.files.as_deref(),
        env_program: spec.env_program.as_deref(),
        wrappers: &state.wrappers,
        cmdline: &command,
    });
    if parts.is_empty() {
        log(format!("{}: launching", spec.name));
    } else {
        log(format!(
            "{}: launching with {}",
            spec.name,
            parts.join(", ")
        ));
    }
    exec(chain::argv(links), &plan)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args(list: &[&str]) -> Vec<OsString> {
        list.iter().map(OsString::from).collect()
    }

    #[test]
    fn dispatch_table() {
        let shell = OsStr::new("/var/lib/steam-config-nix/launch-shell");
        let store = OsStr::new("/nix/store/x/bin/steam-config-launch");
        let cases: Vec<(&OsStr, Vec<OsString>, bool, Mode)> = vec![
            (
                store,
                args(&["launch", "s", "--", "g"]),
                false,
                Mode::Launch(args(&["s", "--", "g"])),
            ),
            (
                store,
                args(&["inner", "s"]),
                false,
                Mode::Inner(args(&["s"])),
            ),
            (
                store,
                args(&["show", "620"]),
                false,
                Mode::Show(args(&["620"])),
            ),
            (shell, args(&["show"]), true, Mode::Show(args(&[]))),
            (
                shell,
                args(&["echo game"]),
                false,
                Mode::Shell("echo game".into()),
            ),
            (
                shell,
                args(&["-c", "echo game"]),
                false,
                Mode::Shell("echo game".into()),
            ),
            (
                shell,
                args(&["echo game", "extra"]),
                false,
                Mode::Shell("echo game".into()),
            ),
            (
                store,
                args(&["echo game"]),
                true,
                Mode::Shell("echo game".into()),
            ),
            (shell, args(&[]), true, Mode::Usage),
            (shell, args(&["-c"]), true, Mode::Usage),
            (store, args(&["620"]), false, Mode::Usage),
            (store, args(&["--help"]), false, Mode::Usage),
            (store, args(&[]), false, Mode::Usage),
        ];
        for (argv0, argv, app, want) in cases {
            assert_eq!(
                dispatch(argv0, &argv, app),
                want,
                "{argv0:?} {argv:?} {app}"
            );
        }
    }

    #[test]
    fn env_rendering_order() {
        let mut spec = spec::parse_app(spec::tests::PORTAL).unwrap();
        spec.env.insert("BAD=NAME".into(), Some("x".into()));
        let mut plan = EnvPlan::with_base(Vec::new());
        plan.extend(
            &[("PROTON_ENABLE_WAYLAND".to_string(), Some("1".to_string()))].into(),
            "global",
        );
        apply_spec_env(&mut plan, &spec);
        plan.set(COMPAT_DATA, "/p", "prefixPath");
        scope::steam_off(&mut plan);
        let order: Vec<(String, Option<String>, &str)> = plan
            .entries
            .iter()
            .map(|e| {
                (
                    e.name.to_string_lossy().into_owned(),
                    e.value.as_ref().map(|v| v.to_string_lossy().into_owned()),
                    e.source,
                )
            })
            .collect();
        let s = |v: &str| Some(v.to_string());
        assert_eq!(
            order,
            [
                ("PROTON_ENABLE_WAYLAND".into(), s("1"), "global"),
                ("DXVK_HUD".into(), s("fps"), "env"),
                ("PROTON_LOG".into(), s("1"), "env"),
                ("TZ".into(), None, "env"),
                (
                    "WINEDLLOVERRIDES".into(),
                    s("d3d9=;winhttp=n,b"),
                    "dllOverrides"
                ),
                (COMPAT_DATA.into(), s("/p"), "prefixPath"),
                (scope::STEAM_SCOPE.into(), s("0"), "systemd"),
            ]
        );
    }

    #[test]
    fn unset_compat_skips_winetricks() {
        let spec = spec::parse_app(spec::tests::PORTAL).unwrap();
        let mut plan = EnvPlan::with_base(vec![(COMPAT_DATA.into(), "/steam/compat".into())]);
        plan.push(COMPAT_DATA, None, "env");
        let orig = plan.get(COMPAT_DATA);
        assert_eq!(orig, None);
        let root = spec::tests::temp("unset-compat");
        std::fs::create_dir_all(root.join("pfx")).unwrap();
        plan.set(COMPAT_DATA, &root, "prefixPath");
        let compat = plan.get(COMPAT_DATA);
        let decision = winetricks::decide(
            spec.winetricks.as_ref().unwrap(),
            &winetricks::Inputs {
                compat: compat.as_deref(),
                orig: orig.as_deref(),
                prefix_path: true,
                app_id: Some(OsStr::new("620")),
            },
        );
        assert_eq!(decision, winetricks::Decision::Skip);
        let _ = std::fs::remove_dir_all(&root);
    }
}
