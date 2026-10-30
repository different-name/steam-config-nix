mod formats;
mod fsutil;
mod launch;
mod layer;
mod mounts;
mod notify;
mod roots;
mod spec;
mod upper;
mod write;

use std::collections::BTreeMap;
use std::ffi::OsString;
use std::fs;
use std::io::Read;
use std::os::fd::FromRawFd;
use std::os::unix::process::{CommandExt, ExitStatusExt};
use std::path::{Path, PathBuf};
use std::process::Command;

use spec::Spec;

pub use notify::log;

fn notify(spec: &Spec, body: &str) {
    notify::notify(spec.notify_send.as_deref(), body);
}

fn usage() -> ! {
    eprintln!(
        "usage: steam-config-launch show <app id or attribute name> [-- <command line>]\n       steam-config-launch launch <spec.json> -- <command...>"
    );
    std::process::exit(2);
}

fn split_command(args: &[OsString]) -> (&[OsString], &[OsString]) {
    match args.iter().position(|a| a == "--") {
        Some(i) => (&args[..i], &args[i + 1..]),
        None => usage(),
    }
}

fn exec(command: &[OsString]) -> ! {
    let Some((bin, rest)) = command.split_first() else {
        usage()
    };
    let err = Command::new(bin).args(rest).exec();
    log(format!("{}: {err}", bin.to_string_lossy()));
    std::process::exit(127);
}

fn data_dir(key: &str) -> Result<PathBuf, String> {
    launch::spec::user_data_base(std::env::var_os("XDG_DATA_HOME"), std::env::var_os("HOME"))
        .map(|base| base.join("steam-config-nix/apps").join(key))
        .ok_or_else(|| "neither XDG_DATA_HOME nor HOME is an absolute path".into())
}

fn runtime_dir(key: &str) -> PathBuf {
    let base = std::env::var("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| std::env::temp_dir());
    base.join("steam-config-nix").join(key)
}

fn resolve_roots(spec: &Spec) -> BTreeMap<String, PathBuf> {
    let mut roots = BTreeMap::new();
    for name in spec.locations.keys() {
        let root = match name.as_str() {
            "game" => roots::game(spec.app_id),
            "prefix" => roots::prefix(),
            _ => None,
        };
        match root {
            Some(root) => {
                roots.insert(name.clone(), root);
            }
            None => log(format!("{name}: not found, its files are skipped")),
        }
    }
    roots
}

fn try_lock(path: &Path) -> Result<fs::File, String> {
    let file = fs::File::create(path).map_err(|e| format!("{}: {e}", path.display()))?;
    use std::os::fd::AsRawFd;
    let rc = unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) };
    if rc != 0 {
        return Err("another launch is using this app's files".into());
    }
    Ok(file)
}

fn ready_pipe() -> Result<(fs::File, i32), String> {
    let mut fds = [0i32; 2];
    if unsafe { libc::pipe2(fds.as_mut_ptr(), libc::O_CLOEXEC) } != 0 {
        return Err(std::io::Error::last_os_error().to_string());
    }
    // the write end is inherited through bwrap by the inner step, which closes it before the game starts
    unsafe { libc::fcntl(fds[1], libc::F_SETFD, 0) };
    Ok((unsafe { fs::File::from_raw_fd(fds[0]) }, fds[1]))
}

fn launch(spec_path: &Path, command: &[OsString]) -> ! {
    let spec = match spec::load(spec_path) {
        Ok(spec) => spec,
        Err(e) => {
            log(e);
            exec(command);
        }
    };
    match prepare_and_run(&spec, spec_path, command) {
        Ok(code) => std::process::exit(code),
        Err(e) => {
            log(format!("{e}, launching {} without its files", spec.name));
            notify(
                &spec,
                &format!("{}: {e}, launched without its files", spec.name),
            );
            exec(command);
        }
    }
}

fn prepare_and_run(spec: &Spec, spec_path: &Path, command: &[OsString]) -> Result<i32, String> {
    let data = data_dir(&spec.key)?;
    fs::create_dir_all(&data).map_err(|e| format!("{}: {e}", data.display()))?;
    let _lock = try_lock(&data.join("lock"))?;
    let roots = resolve_roots(spec);
    let roots_json = serde_json::to_string(&roots).map_err(|e| e.to_string())?;
    let mounted = roots.keys().any(|loc| spec.locations[loc].mounted());
    let inner_args = |ready: Option<i32>| -> Vec<OsString> {
        let mut args: Vec<OsString> = vec!["inner".into()];
        if let Some(fd) = ready {
            args.push("--ready-fd".into());
            args.push(fd.to_string().into());
        }
        args.push(spec_path.into());
        args.push(roots_json.clone().into());
        args.push("--".into());
        args.extend(command.iter().cloned());
        args
    };
    if !mounted {
        let err = Command::new(std::env::current_exe().map_err(|e| e.to_string())?)
            .args(inner_args(None))
            .exec();
        return Err(err.to_string());
    }

    let cwd = std::env::current_dir().map_err(|e| e.to_string())?;
    let mut plan = mounts::Plan { args: Vec::new() };
    plan.args.extend([
        "--dev-bind".into(),
        "/".into(),
        "/".into(),
        "--chdir".into(),
        cwd.into(),
        "--die-with-parent".into(),
    ]);
    let layers = data.join("layer");
    for stale in layer::previous(&layers, None) {
        if !stale
            .file_name()
            .and_then(|n| n.to_str())
            .is_some_and(|n| spec.locations.contains_key(n))
        {
            let _ = fsutil::remove_any(&stale);
        }
    }
    for (name, root) in &roots {
        let location = &spec.locations[name];
        if !location.mounted() {
            continue;
        }
        let base = layers.join(name);
        let layer = location
            .layer
            .as_deref()
            .map(|store| layer::materialise(store, &base))
            .transpose()?;
        let previous = layer::previous(&base, layer.as_deref());
        let upper_dir = data.join("writes").join(name);
        let work_dir = data.join("work").join(name);
        let declared: Vec<&str> = location.declared().collect();
        upper::prepare(&upper_dir, root, &declared, layer.as_deref(), &previous)?;
        layer::sweep(&base, layer.as_deref());
        let hide = runtime_dir(&spec.key).join(name);
        mounts::compose(
            &mut plan,
            location,
            &mounts::Dirs {
                root,
                layer: layer.as_deref(),
                hide: &hide,
                upper: &upper_dir,
                work: &work_dir,
            },
        )?;
    }

    let (mut ready_read, ready_write) = ready_pipe()?;
    let me = std::env::current_exe().map_err(|e| e.to_string())?;
    let mut child = Command::new(&spec.bwrap)
        .args(&plan.args)
        .arg("--")
        .arg(&me)
        .args(inner_args(Some(ready_write)))
        .spawn()
        .map_err(|e| format!("{}: {e}", spec.bwrap.display()))?;
    unsafe { libc::close(ready_write) };
    let mut byte = [0u8; 1];
    let started = matches!(ready_read.read(&mut byte), Ok(1));
    if !started {
        let _ = child.wait();
        return Err("the file mounts could not be set up".into());
    }
    let status = child.wait().map_err(|e| e.to_string())?;
    Ok(status
        .code()
        .unwrap_or_else(|| 128 + status.signal().unwrap_or(0)))
}

fn inner(args: &[OsString]) -> ! {
    let mut args = args.to_vec();
    let mut ready_fd = None;
    if args.first().is_some_and(|a| a == "--ready-fd") {
        ready_fd = args
            .get(1)
            .and_then(|s| s.to_str())
            .and_then(|s| s.parse::<i32>().ok());
        args.drain(..2);
    }
    // running here means the mounts are up, and every exit path below execs the game
    if let Some(fd) = ready_fd {
        unsafe {
            libc::write(fd, b"1".as_ptr().cast(), 1);
            libc::close(fd);
        }
    }
    let (own, command) = split_command(&args);
    let [spec_path, roots_json] = own else {
        usage()
    };
    let spec = spec::load(Path::new(spec_path)).unwrap_or_else(|e| {
        log(e);
        exec(command)
    });
    let roots: BTreeMap<String, PathBuf> = roots_json
        .to_str()
        .and_then(|s| serde_json::from_str(s).ok())
        .unwrap_or_default();
    let originals = match data_dir(&spec.key) {
        Ok(data) => data.join("originals"),
        Err(e) => {
            log(e);
            exec(command)
        }
    };
    let mut failures = Vec::new();
    for (name, root) in &roots {
        failures.extend(write::apply(
            &spec.locations[name],
            name,
            root,
            &originals.join(name),
        ));
    }
    for failure in &failures {
        log(failure);
    }
    if !failures.is_empty() {
        notify(
            &spec,
            &format!(
                "{}: {} file{} could not be written",
                spec.name,
                failures.len(),
                if failures.len() == 1 { "" } else { "s" }
            ),
        );
    }
    exec(command);
}

fn main() {
    let mut argv = std::env::args_os();
    let argv0 = argv.next().unwrap_or_default();
    let args: Vec<OsString> = argv.collect();
    let steam_app_id = std::env::var_os("SteamAppId").is_some_and(|v| !v.is_empty());
    match launch::dispatch(&argv0, &args, steam_app_id) {
        launch::Mode::Launch(rest) => {
            let (own, command) = split_command(&rest);
            let [spec_path] = own else { usage() };
            launch(Path::new(spec_path), command)
        }
        launch::Mode::Inner(rest) => inner(&rest),
        launch::Mode::Show(rest) => launch::show::main(&rest),
        launch::Mode::Shell(cmdline) => launch::shell(cmdline),
        launch::Mode::Usage => usage(),
    }
}
