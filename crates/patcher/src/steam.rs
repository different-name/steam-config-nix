use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread::sleep;
use std::time::{Duration, Instant};

use steam_config_vdf::text::parse;

use crate::log;

const SHUTDOWN_TIMEOUT: Duration = Duration::from_secs(30);
const SETTLE: Duration = Duration::from_secs(2);
const POLL: Duration = Duration::from_secs(1);

pub fn home() -> PathBuf {
    PathBuf::from(std::env::var("HOME").unwrap_or_default())
}

pub fn steam_dir() -> Option<PathBuf> {
    let home = home();
    [".steam/root", ".steam/steam", ".local/share/Steam"]
        .iter()
        .map(|rel| home.join(rel))
        .find(|p| p.is_dir())
        .and_then(|p| fs::canonicalize(p).ok())
}

pub fn user_ids(steam_dir: &Path) -> Vec<u32> {
    let Ok(entries) = fs::read_dir(steam_dir.join("userdata")) else {
        return Vec::new();
    };
    let mut ids: Vec<u32> = entries
        .flatten()
        .filter(|e| e.path().is_dir())
        .filter_map(|e| e.file_name().to_str()?.parse().ok())
        .filter(|id| *id != 0)
        .collect();
    ids.sort_unstable();
    ids
}

pub fn library_paths(steam_dir: &Path) -> Vec<PathBuf> {
    let mut paths = vec![steam_dir.to_path_buf()];
    for rel in ["config/libraryfolders.vdf", "steamapps/libraryfolders.vdf"] {
        let file = steam_dir.join(rel);
        let Ok(text) = fs::read_to_string(&file) else {
            continue;
        };
        if let Ok(root) = parse(&text) {
            for folders in root
                .children()
                .filter(|n| n.name.eq_ignore_ascii_case("libraryfolders"))
            {
                for folder in folders.children().filter(|n| n.children.is_some()) {
                    if let Some(path) = folder.find("path").and_then(|p| p.value.clone()) {
                        paths.push(PathBuf::from(path));
                    }
                }
            }
        }
        break;
    }
    let mut unique: Vec<PathBuf> = Vec::new();
    for path in paths {
        if !unique.contains(&path) {
            unique.push(path);
        }
    }
    unique
}

pub fn find_app_manifest(steam_dir: &Path, app_id: u32) -> Option<PathBuf> {
    library_paths(steam_dir)
        .into_iter()
        .map(|lib| {
            lib.join("steamapps")
                .join(format!("appmanifest_{app_id}.acf"))
        })
        .find(|p| p.is_file())
}

fn uid_of(pid: i32) -> Option<u32> {
    let status = fs::read_to_string(format!("/proc/{pid}/status")).ok()?;
    status
        .lines()
        .find_map(|l| l.strip_prefix("Uid:"))?
        .split_whitespace()
        .next()?
        .parse()
        .ok()
}

fn cmdline(pid: i32) -> Vec<String> {
    fs::read(format!("/proc/{pid}/cmdline"))
        .map(|b| {
            b.split(|&c| c == 0)
                .filter(|a| !a.is_empty())
                .map(|a| String::from_utf8_lossy(a).into_owned())
                .collect()
        })
        .unwrap_or_default()
}

pub fn processes(comm: &str, uid: u32, arg: Option<&str>) -> Vec<i32> {
    let Ok(entries) = fs::read_dir("/proc") else {
        return Vec::new();
    };
    entries
        .flatten()
        .filter_map(|e| e.file_name().to_str()?.parse::<i32>().ok())
        .filter(|pid| {
            fs::read_to_string(format!("/proc/{pid}/comm"))
                .map(|c| c.trim_end() == comm)
                .unwrap_or(false)
        })
        .filter(|pid| uid_of(*pid) == Some(uid))
        .filter(|pid| arg.is_none_or(|a| cmdline(*pid).iter().any(|c| c == a)))
        .collect()
}

fn own_uid() -> u32 {
    unsafe { libc::getuid() }
}

pub fn steam_pids() -> Vec<i32> {
    processes("steam", own_uid(), None)
}

pub fn game_pids() -> Vec<i32> {
    processes("reaper", own_uid(), Some("SteamLaunch"))
}

pub fn steam_is_running() -> bool {
    !steam_pids().is_empty()
}

pub fn game_is_running() -> bool {
    !game_pids().is_empty()
}

fn alive(pid: i32) -> bool {
    Path::new(&format!("/proc/{pid}")).exists()
        && fs::read_to_string(format!("/proc/{pid}/status"))
            .map(|s| {
                !s.lines()
                    .any(|l| l.starts_with("State:") && l.contains("Z ("))
            })
            .unwrap_or(false)
}

pub fn wait_for_exit(pids: &[i32], timeout: Option<Duration>) -> Vec<i32> {
    let start = Instant::now();
    loop {
        let remaining: Vec<i32> = pids.iter().copied().filter(|p| alive(*p)).collect();
        if remaining.is_empty() {
            return remaining;
        }
        if timeout.is_some_and(|t| start.elapsed() >= t) {
            return remaining;
        }
        sleep(POLL);
    }
}

pub fn wait_for_steam_exit() {
    while steam_is_running() {
        sleep(POLL);
    }
    sleep(SETTLE);
}

pub fn wait_for_game_exit() {
    while game_is_running() {
        sleep(POLL);
    }
}

fn signal(pids: &[i32], sig: libc::c_int) {
    for pid in pids {
        unsafe {
            libc::kill(*pid, sig);
        }
    }
}

pub fn stop(pids: &[i32], timeout: Duration) {
    let remaining = wait_for_exit(pids, Some(timeout));
    if remaining.is_empty() {
        return;
    }
    signal(&remaining, libc::SIGTERM);
    let remaining = wait_for_exit(&remaining, Some(timeout));
    if remaining.is_empty() {
        return;
    }
    signal(&remaining, libc::SIGKILL);
    wait_for_exit(&remaining, Some(timeout));
}

pub fn shutdown(steam: &Path, timeout: Duration) {
    let child = Command::new(steam)
        .arg("-shutdown")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();
    let mut child = match child {
        Ok(child) => child,
        Err(e) => {
            log(format!("{} -shutdown: {e}", steam.display()));
            return;
        }
    };
    let start = Instant::now();
    loop {
        match child.try_wait() {
            Ok(Some(_)) => return,
            Ok(None) if start.elapsed() < timeout => sleep(Duration::from_millis(200)),
            _ => {
                let _ = child.kill();
                let _ = child.wait();
                return;
            }
        }
    }
}

pub fn close_steam(steam: &Path) {
    let pids = steam_pids();
    if pids.is_empty() {
        return;
    }
    shutdown(steam, SHUTDOWN_TIMEOUT);
    stop(&pids, SHUTDOWN_TIMEOUT);
    sleep(SETTLE);
}

#[cfg(test)]
mod tests {
    use super::{find_app_manifest, library_paths, own_uid, processes, shutdown, stop, user_ids};
    use std::fs;
    use std::path::PathBuf;
    use std::process::{Command, Stdio};
    use std::time::Duration;

    fn temp(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("scn-steam-{}-{name}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn write_libraryfolders(steam_dir: &PathBuf, paths: &[&PathBuf]) {
        fs::create_dir_all(steam_dir.join("config")).unwrap();
        let blocks: String = paths
            .iter()
            .enumerate()
            .map(|(i, p)| {
                format!(
                    "\t\"{i}\"\n\t{{\n\t\t\"path\"\t\t\"{}\"\n\t}}\n",
                    p.display()
                )
            })
            .collect();
        fs::write(
            steam_dir.join("config/libraryfolders.vdf"),
            format!("\"libraryfolders\"\n{{\n{blocks}}}\n"),
        )
        .unwrap();
    }

    #[test]
    fn library_paths_include_steam_dir_and_extra_libraries() {
        let root = temp("libs");
        let steam_dir = root.join("steam");
        let extra = root.join("drive");
        write_libraryfolders(&steam_dir, &[&steam_dir, &extra]);
        assert_eq!(library_paths(&steam_dir), vec![steam_dir.clone(), extra]);
    }

    #[test]
    fn library_paths_without_libraryfolders() {
        let root = temp("nolibs");
        let steam_dir = root.join("steam");
        fs::create_dir_all(&steam_dir).unwrap();
        assert_eq!(library_paths(&steam_dir), vec![steam_dir]);
    }

    #[test]
    fn find_app_manifest_searches_all_libraries() {
        let root = temp("manifest");
        let steam_dir = root.join("steam");
        let extra = root.join("drive");
        write_libraryfolders(&steam_dir, &[&steam_dir, &extra]);
        let manifest = extra.join("steamapps/appmanifest_620.acf");
        fs::create_dir_all(manifest.parent().unwrap()).unwrap();
        fs::write(&manifest, "").unwrap();
        assert_eq!(find_app_manifest(&steam_dir, 620), Some(manifest));
        assert_eq!(find_app_manifest(&steam_dir, 621), None);
    }

    #[test]
    fn user_ids_are_numeric_dirs_excluding_zero() {
        let root = temp("users");
        for name in ["111", "222", "0", "ac", "anonymous"] {
            fs::create_dir_all(root.join("userdata").join(name)).unwrap();
        }
        fs::write(root.join("userdata/333"), "").unwrap();
        assert_eq!(user_ids(&root), vec![111, 222]);
        assert!(user_ids(&root.join("missing")).is_empty());
    }

    #[test]
    fn processes_match_comm_uid_and_argument() {
        let comm = fs::read_to_string("/proc/self/comm").unwrap();
        let me = std::process::id() as i32;
        assert!(processes(comm.trim_end(), own_uid(), None).contains(&me));
        assert!(!processes(comm.trim_end(), own_uid() + 1, None).contains(&me));
        assert!(!processes(comm.trim_end(), own_uid(), Some("no-such-argument")).contains(&me));
        assert!(processes("no-such-process-name", own_uid(), None).is_empty());
    }

    #[test]
    fn stop_escalates_from_term_to_kill() {
        let mut child = Command::new("/bin/sh")
            .args(["-c", "trap '' TERM; while :; do sleep 1; done"])
            .stdout(Stdio::null())
            .spawn()
            .unwrap();
        let pid = child.id() as i32;
        stop(&[pid], Duration::from_secs(2));
        let status = child.wait().unwrap();
        assert!(!status.success());
        assert!(super::wait_for_exit(&[pid], Some(Duration::from_secs(1))).is_empty());
    }

    #[test]
    fn stop_terminates_a_cooperative_process() {
        let mut child = Command::new("/bin/sh")
            .args(["-c", "sleep 30"])
            .stdout(Stdio::null())
            .spawn()
            .unwrap();
        let pid = child.id() as i32;
        stop(&[pid], Duration::from_secs(2));
        assert!(!child.wait().unwrap().success());
    }

    #[test]
    fn shutdown_runs_the_command_and_kills_a_hung_one() {
        let root = temp("shutdown");
        let marker = root.join("ran");
        let script = root.join("steam");
        fs::write(
            &script,
            format!(
                "#!/bin/sh\n[ \"$1\" = -shutdown ] && touch {}\n",
                marker.display()
            ),
        )
        .unwrap();
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(&script, fs::Permissions::from_mode(0o755)).unwrap();
        shutdown(&script, Duration::from_secs(5));
        assert!(marker.exists());
        let hung = root.join("hung");
        fs::write(&hung, "#!/bin/sh\nsleep 30\n").unwrap();
        fs::set_permissions(&hung, fs::Permissions::from_mode(0o755)).unwrap();
        let start = std::time::Instant::now();
        shutdown(&hung, Duration::from_millis(500));
        assert!(start.elapsed() < Duration::from_secs(10));
        shutdown(&root.join("missing"), Duration::from_secs(1));
    }
}
