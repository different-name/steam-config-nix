use std::ffi::OsString;
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::os::fd::{AsRawFd, FromRawFd};
use std::os::unix::ffi::OsStringExt;
use std::os::unix::process::{CommandExt, ExitStatusExt};
use std::path::Path;
use std::process::Command;

use super::cmdline::quote;
use super::env::EnvPlan;
use crate::notify::log;

#[derive(Debug, PartialEq, Clone)]
pub struct State {
    pub cmdline: String,
    pub wrappers: Vec<String>,
    pub args: Vec<String>,
}

#[derive(Debug, PartialEq, Clone, Copy)]
pub struct Limit {
    pub resource: i32,
    pub soft: u64,
    pub hard: u64,
}

#[derive(Debug, PartialEq, Default)]
pub struct Process {
    pub cwd: OsString,
    pub umask: Option<u32>,
    pub limits: Vec<Limit>,
}

pub type Env = Vec<(OsString, OsString)>;

#[derive(Debug, PartialEq)]
pub enum Outcome {
    Continue(State, Env, Process),
    Exited(i32),
}

const LIMITS: [(&str, i32); 16] = [
    ("Max cpu time", libc::RLIMIT_CPU as i32),
    ("Max file size", libc::RLIMIT_FSIZE as i32),
    ("Max data size", libc::RLIMIT_DATA as i32),
    ("Max stack size", libc::RLIMIT_STACK as i32),
    ("Max core file size", libc::RLIMIT_CORE as i32),
    ("Max resident set", libc::RLIMIT_RSS as i32),
    ("Max processes", libc::RLIMIT_NPROC as i32),
    ("Max open files", libc::RLIMIT_NOFILE as i32),
    ("Max locked memory", libc::RLIMIT_MEMLOCK as i32),
    ("Max address space", libc::RLIMIT_AS as i32),
    ("Max file locks", libc::RLIMIT_LOCKS as i32),
    ("Max pending signals", libc::RLIMIT_SIGPENDING as i32),
    ("Max msgqueue size", libc::RLIMIT_MSGQUEUE as i32),
    ("Max nice priority", libc::RLIMIT_NICE as i32),
    ("Max realtime priority", libc::RLIMIT_RTPRIO as i32),
    ("Max realtime timeout", libc::RLIMIT_RTTIME as i32),
];

fn limit_value(s: &str) -> Option<u64> {
    if s == "unlimited" {
        return Some(libc::RLIM_INFINITY as u64);
    }
    s.parse().ok()
}

pub fn parse_limits(text: &str) -> Vec<Limit> {
    text.lines()
        .filter_map(|line| {
            let (name, resource) = LIMITS.iter().find(|(n, _)| line.starts_with(n))?;
            let mut cols = line[name.len()..].split_whitespace();
            Some(Limit {
                resource: *resource,
                soft: limit_value(cols.next()?)?,
                hard: limit_value(cols.next()?)?,
            })
        })
        .collect()
}

fn current_limit(resource: i32) -> Option<(u64, u64)> {
    let mut cur = libc::rlimit {
        rlim_cur: 0,
        rlim_max: 0,
    };
    let rc = unsafe { libc::getrlimit(resource as _, &mut cur) };
    (rc == 0).then_some((cur.rlim_cur as u64, cur.rlim_max as u64))
}

pub fn apply_process(process: &Process) {
    if !process.cwd.is_empty() {
        if let Err(e) = std::env::set_current_dir(&process.cwd) {
            log(format!("preHook cd {}: {e}", process.cwd.to_string_lossy()));
        }
    }
    if let Some(mask) = process.umask {
        unsafe { libc::umask(mask as libc::mode_t) };
    }
    for limit in &process.limits {
        if current_limit(limit.resource) == Some((limit.soft, limit.hard)) {
            continue;
        }
        let new = libc::rlimit {
            rlim_cur: limit.soft as _,
            rlim_max: limit.hard as _,
        };
        if unsafe { libc::setrlimit(limit.resource as _, &new) } != 0 {
            log(format!(
                "preHook ulimit {}: {}",
                limit.resource,
                std::io::Error::last_os_error()
            ));
        }
    }
}

fn array(name: &str, items: &[String]) -> String {
    let quoted: Vec<String> = items.iter().map(|i| quote(i)).collect();
    format!("{name}=({})\n", quoted.join(" "))
}

pub fn script(hook: &str, state: &State, fd: i32) -> String {
    let mut s = format!("cmdline={}\n", quote(&state.cmdline));
    s += &array("wrappers", &state.wrappers);
    s += &array("args", &state.args);
    s += "set -- \"$cmdline\"\n";
    s += hook;
    // a blank line so a trailing comment or backslash in the hook cannot swallow the epilogue
    s += &format!(
        "\n\n{{ printf '%s\\0' \"$cmdline\" \"${{#wrappers[@]}}\" \"${{wrappers[@]}}\" \"${{#args[@]}}\" \"${{args[@]}}\" \"$PWD\" \"$(umask)\" \"$(</proc/$$/limits)\"; env -0; }} >&{fd}\n"
    );
    s
}

fn utf8(field: &[u8], what: &str) -> Result<String, String> {
    String::from_utf8(field.to_vec()).map_err(|_| format!("preHook left {what} that is not UTF-8"))
}

pub fn parse(bytes: &[u8]) -> Result<(State, Env, Process), String> {
    let mut fields = bytes.split(|b| *b == 0);
    let mut next = |what: &str| {
        fields
            .next()
            .ok_or_else(|| format!("preHook output ended before {what}"))
    };
    let cmdline = utf8(next("cmdline")?, "cmdline")?;
    let mut list = |what: &str| -> Result<Vec<String>, String> {
        let count: usize = utf8(next(what)?, what)?
            .parse()
            .map_err(|_| format!("preHook output has no {what} count"))?;
        (0..count).map(|_| utf8(next(what)?, what)).collect()
    };
    let wrappers = list("wrappers")?;
    let args = list("args")?;
    let process = Process {
        cwd: OsString::from_vec(next("the working directory")?.to_vec()),
        umask: std::str::from_utf8(next("umask")?)
            .ok()
            .and_then(|m| u32::from_str_radix(m.trim(), 8).ok()),
        limits: parse_limits(&String::from_utf8_lossy(next("limits")?)),
    };
    let mut env = Vec::new();
    for entry in fields.filter(|f| !f.is_empty()) {
        let Some(eq) = entry.iter().position(|b| *b == b'=').filter(|i| *i > 0) else {
            continue;
        };
        if &entry[..eq] == b"_" {
            continue;
        }
        env.push((
            OsString::from_vec(entry[..eq].to_vec()),
            OsString::from_vec(entry[eq + 1..].to_vec()),
        ));
    }
    Ok((
        State {
            cmdline,
            wrappers,
            args,
        },
        env,
        process,
    ))
}

fn memfd() -> Result<File, String> {
    let err = || format!("preHook: {}", std::io::Error::last_os_error());
    let low =
        unsafe { libc::memfd_create(c"steam-config-nix-prehook".as_ptr(), libc::MFD_CLOEXEC) };
    if low < 0 {
        return Err(err());
    }
    let low = unsafe { File::from_raw_fd(low) };
    // above the fds a hook is likely to redirect itself
    let fd = unsafe { libc::fcntl(low.as_raw_fd(), libc::F_DUPFD_CLOEXEC, 200) };
    if fd < 0 {
        return Err(err());
    }
    Ok(unsafe { File::from_raw_fd(fd) })
}

pub fn run(shell: &Path, hook: &str, state: &State, plan: &EnvPlan) -> Result<Outcome, String> {
    let mut out = memfd()?;
    let fd = out.as_raw_fd();
    let mut cmd = Command::new(shell);
    cmd.arg("-c")
        .arg(script(hook, state, fd))
        .arg("steam-config-nix");
    plan.apply(&mut cmd);
    unsafe {
        cmd.pre_exec(move || {
            if libc::fcntl(fd, libc::F_SETFD, 0) != 0 {
                return Err(std::io::Error::last_os_error());
            }
            Ok(())
        });
    }
    let status = cmd
        .status()
        .map_err(|e| format!("{}: {e}", shell.display()))?;
    let code = status
        .code()
        .unwrap_or_else(|| 128 + status.signal().unwrap_or(0));
    if code != 0 {
        return Ok(Outcome::Exited(code));
    }
    let mut bytes = Vec::new();
    out.seek(SeekFrom::Start(0))
        .and_then(|_| out.read_to_end(&mut bytes))
        .map_err(|e| format!("preHook: {e}"))?;
    if bytes.is_empty() {
        return Ok(Outcome::Exited(0));
    }
    let (state, env, process) = parse(&bytes)?;
    Ok(Outcome::Continue(state, env, process))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn bash() -> Option<std::path::PathBuf> {
        let path = std::env::var_os("PATH")?;
        std::env::split_paths(&path)
            .map(|d| d.join("bash"))
            .find(|p| p.is_file())
    }

    fn state() -> State {
        State {
            cmdline: "'/g/run' -x".into(),
            wrappers: vec!["/g/gamescope".into(), "two words".into(), "--".into()],
            args: vec!["-a".into(), "it's".into()],
        }
    }

    fn base() -> EnvPlan {
        EnvPlan::with_base(vec![
            ("PATH".into(), std::env::var_os("PATH").unwrap_or_default()),
            ("KEEP".into(), "k".into()),
            ("DROP".into(), "d".into()),
        ])
    }

    fn get<'a>(env: &'a [(OsString, OsString)], name: &str) -> Option<&'a OsString> {
        env.iter().find(|(n, _)| n == name).map(|(_, v)| v)
    }

    #[test]
    fn parse_layout() {
        let bytes = b"c\x002\x00w1\x00w 2\x000\x00/w\x000077\x00Max open files            512                  4096                 files     \x00A=1\x00_=/bin/env\x00B=x=y\nz\x00";
        let (state, env, process) = parse(bytes).unwrap();
        assert_eq!(state.cmdline, "c");
        assert_eq!(state.wrappers, ["w1", "w 2"]);
        assert!(state.args.is_empty());
        assert_eq!(
            env,
            [("A".into(), "1".into()), ("B".into(), "x=y\nz".into())]
        );
        assert_eq!(
            process,
            Process {
                cwd: "/w".into(),
                umask: Some(0o077),
                limits: vec![Limit {
                    resource: libc::RLIMIT_NOFILE as i32,
                    soft: 512,
                    hard: 4096,
                }],
            }
        );
        assert!(parse(b"c\x00x\x00").is_err());
    }

    #[test]
    fn limits_table() {
        let text = "Limit                     Soft Limit           Hard Limit           Units     \nMax cpu time              unlimited            unlimited            seconds   \nMax file size             unlimited            unlimited            bytes     \nMax realtime timeout      200000               unlimited            us        \n";
        let inf = libc::RLIM_INFINITY as u64;
        assert_eq!(
            parse_limits(text),
            [
                Limit {
                    resource: libc::RLIMIT_CPU as i32,
                    soft: inf,
                    hard: inf
                },
                Limit {
                    resource: libc::RLIMIT_FSIZE as i32,
                    soft: inf,
                    hard: inf
                },
                Limit {
                    resource: libc::RLIMIT_RTTIME as i32,
                    soft: 200000,
                    hard: inf
                },
            ]
        );
    }

    #[test]
    fn round_trip_unchanged() {
        let Some(bash) = bash() else { return };
        let Outcome::Continue(got, env, process) = run(&bash, "", &state(), &base()).unwrap()
        else {
            panic!("hook did not continue")
        };
        assert_eq!(got, state());
        assert_eq!(get(&env, "KEEP").unwrap(), "k");
        assert_eq!(
            process.cwd,
            std::env::current_dir().unwrap().into_os_string()
        );
        let nofile = libc::RLIMIT_NOFILE as i32;
        let limit = process
            .limits
            .iter()
            .find(|l| l.resource == nofile)
            .unwrap();
        assert_eq!(current_limit(nofile), Some((limit.soft, limit.hard)));
    }

    #[test]
    fn hook_edits_carry() {
        let Some(bash) = bash() else { return };
        let hook = "# comment\nexport NEW=\"$1|${args[1]}\"\nunset DROP\ncmdline=\"$cmdline --late\"\nwrappers=()\nargs+=(\"b c\")\n[[ -n $KEEP ]] && declare -a x=(1) # trailing";
        let Outcome::Continue(got, env, _) = run(&bash, hook, &state(), &base()).unwrap() else {
            panic!("hook did not continue")
        };
        assert_eq!(got.cmdline, "'/g/run' -x --late");
        assert!(got.wrappers.is_empty());
        assert_eq!(got.args, ["-a", "it's", "b c"]);
        assert_eq!(get(&env, "NEW").unwrap(), "'/g/run' -x|it's");
        assert_eq!(get(&env, "DROP"), None);
    }

    #[test]
    fn hook_process_state_carries() {
        let Some(bash) = bash() else { return };
        let hook =
            "cd /\numask 027\nn=$(ulimit -Sn)\n[[ $n = unlimited ]] || ulimit -Sn $((n - 1))";
        let Outcome::Continue(_, env, process) = run(&bash, hook, &state(), &base()).unwrap()
        else {
            panic!("hook did not continue")
        };
        assert_eq!(process.cwd, "/");
        assert_eq!(get(&env, "PWD").unwrap(), "/");
        assert_eq!(process.umask, Some(0o027));
        let nofile = libc::RLIMIT_NOFILE as i32;
        let (soft, _) = current_limit(nofile).unwrap();
        let limit = process
            .limits
            .iter()
            .find(|l| l.resource == nofile)
            .unwrap();
        if soft != libc::RLIM_INFINITY as u64 {
            assert_eq!(limit.soft, soft - 1);
        }
    }

    #[test]
    fn hook_redirecting_low_fds_continues() {
        let Some(bash) = bash() else { return };
        let hook = "for n in {3..30}; do eval \"exec $n>/dev/null\"; done";
        assert!(matches!(
            run(&bash, hook, &state(), &base()).unwrap(),
            Outcome::Continue(s, _, _) if s == state()
        ));
    }

    #[test]
    fn trailing_backslash_continues() {
        let Some(bash) = bash() else { return };
        assert!(matches!(
            run(&bash, "true \\", &state(), &base()).unwrap(),
            Outcome::Continue(s, _, _) if s == state()
        ));
    }

    #[test]
    fn hook_exit_aborts() {
        let Some(bash) = bash() else { return };
        assert_eq!(
            run(&bash, "exit 3", &state(), &base()).unwrap(),
            Outcome::Exited(3)
        );
        assert_eq!(
            run(&bash, "exit 0", &state(), &base()).unwrap(),
            Outcome::Exited(0)
        );
        assert!(matches!(
            run(&bash, "false", &state(), &base()).unwrap(),
            Outcome::Continue(s, _, _) if s == state()
        ));
    }
}
