mod appinfo;
mod compat;
mod fileio;
mod managed;
mod record;
mod state;
mod steam;
mod writers;

use std::collections::BTreeSet;
use std::fs;
use std::os::fd::AsRawFd;
use std::path::{Path, PathBuf};
use std::process::Command;

use record::Record;
use state::{OnSteamRunning, State};
use writers::Outcome;

pub fn log(msg: impl AsRef<str>) {
    eprintln!("steam-config-nix: {}", msg.as_ref());
}

fn notify(state: &State, body: &str) {
    let Some(bin) = &state.notify_send else {
        return;
    };
    let _ = Command::new(bin)
        .args(["-a", "steam-config-nix", "steam-config-nix", body])
        .env_remove("LD_LIBRARY_PATH")
        .env_remove("LD_PRELOAD")
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status();
}

fn usage() -> ! {
    eprintln!("usage: steam-config-patcher <state.json>...");
    std::process::exit(2);
}

fn data_home() -> PathBuf {
    std::env::var("XDG_DATA_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| steam::home().join(".local/share"))
}

fn data_dirs() -> Vec<PathBuf> {
    std::env::var("XDG_DATA_DIRS")
        .ok()
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "/usr/local/share:/usr/share".into())
        .split(':')
        .filter(|s| !s.is_empty())
        .map(PathBuf::from)
        .collect()
}

enum Lock {
    Held(fs::File),
    Busy,
}

fn lock(path: &Path) -> std::io::Result<Lock> {
    let file = fs::File::create(path)?;
    let rc = unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) };
    if rc == 0 {
        return Ok(Lock::Held(file));
    }
    let err = std::io::Error::last_os_error();
    if err.raw_os_error() == Some(libc::EWOULDBLOCK) {
        Ok(Lock::Busy)
    } else {
        Err(err)
    }
}

fn load_state(path: &Path) -> State {
    match State::load(path) {
        Ok(state) => state,
        Err(e) => {
            log(e);
            std::process::exit(1);
        }
    }
}

fn prepare(
    state: &State,
    steam_dir: &Path,
    users: &[u32],
    record: &Record,
) -> (Vec<Outcome>, Vec<String>) {
    let mut outcomes = Vec::new();
    let mut failed = Vec::new();
    let mut collect = |description: String, result: Result<Option<Outcome>, String>| match result {
        Ok(Some(outcome)) => outcomes.push(outcome),
        Ok(None) => {}
        Err(e) => {
            log(format!("{description}: {e}"));
            failed.push(description);
        }
    };
    collect(
        "config.vdf".into(),
        writers::config_vdf::prepare(state, steam_dir, record),
    );
    for id in writers::appmanifest::ids(state, record) {
        collect(
            format!("appmanifest_{id}.acf"),
            writers::appmanifest::prepare(state, steam_dir, id, record),
        );
    }
    for uid in users {
        collect(
            format!("localconfig.vdf (user {uid})"),
            writers::localconfig::prepare(state, steam_dir, *uid, record),
        );
        collect(
            format!("shortcuts.vdf (user {uid})"),
            writers::shortcuts::prepare(state, steam_dir, *uid, record),
        );
    }
    collect(
        "libraryfolders.vdf".into(),
        writers::libraryfolders::prepare(state, steam_dir, record),
    );
    (outcomes, failed)
}

fn main() {
    let args: Vec<PathBuf> = std::env::args_os().skip(1).map(PathBuf::from).collect();
    if args.is_empty() {
        usage();
    }
    let data_dir = data_home().join("steam-config-nix");
    if let Err(e) = fs::create_dir_all(&data_dir) {
        log(format!("{}: {e}", data_dir.display()));
        std::process::exit(1);
    }
    let _lock = match lock(&data_dir.join("patcher.lock")) {
        Ok(Lock::Held(file)) => file,
        Ok(Lock::Busy) => {
            log("another run is in progress");
            std::process::exit(0);
        }
        Err(e) => {
            log(format!("patcher.lock: {e}"));
            std::process::exit(1);
        }
    };
    let Some(state_path) = args.iter().find(|p| p.exists()) else {
        log("no state file");
        std::process::exit(1);
    };
    let mut state = load_state(state_path);
    let Some(steam_dir) = steam::steam_dir() else {
        log("Steam has not been run yet");
        std::process::exit(0);
    };
    let users = steam::user_ids(&steam_dir);
    let record_path = data_dir.join("prior.json");
    let mut record = match Record::load(&record_path) {
        Ok(record) => record,
        Err(e) => {
            log(format!("prior.json: {e}, treating it as empty"));
            Record::default()
        }
    };

    let (mut outcomes, mut failed) = prepare(&state, &steam_dir, &users, &record);
    let mut skipped = false;
    if outcomes.iter().any(|o| o.bytes.is_some()) && steam::steam_is_running() {
        match state.on_steam_running {
            OnSteamRunning::Skip => {
                let msg = "Steam is running, its settings are applied on the next activation after it is closed";
                log(msg);
                notify(&state, msg);
                outcomes.clear();
                skipped = true;
            }
            OnSteamRunning::Wait => {
                log("Steam is running, waiting for it to exit");
                steam::wait_for_steam_exit();
            }
            OnSteamRunning::Close => {
                if steam::game_is_running() {
                    log("a game is running, waiting for it to exit before closing Steam");
                    steam::wait_for_game_exit();
                }
                steam::close_steam(&state.steam);
            }
            OnSteamRunning::ForceClose => steam::close_steam(&state.steam),
        }
        if !skipped {
            state = load_state(state_path);
            (outcomes, failed) = prepare(&state, &steam_dir, &users, &record);
        }
    }

    let mut written = Vec::new();
    for outcome in outcomes {
        if let Some(bytes) = &outcome.bytes {
            if let Err(e) = fileio::write_atomic(&outcome.path, bytes) {
                log(format!("{}: {e}", outcome.description));
                failed.push(outcome.description);
                continue;
            }
            for note in &outcome.notes {
                log(note);
            }
            written.push(outcome.description);
        }
        record.apply(outcome.delta);
    }
    if !skipped {
        if written.is_empty() {
            log("Steam's settings already match");
        } else {
            log(format!("wrote {}", written.join(", ")));
        }
    }

    let desired_grid = writers::grid::desired(&state);
    for uid in &users {
        let grid_dir = steam_dir.join(format!("userdata/{uid}/config/grid"));
        let written = writers::grid::apply(&grid_dir, &desired_grid, &record.grid_for(*uid));
        record.grid.insert(uid.to_string(), written);
    }
    let icon_ids: BTreeSet<u32> = state
        .apps
        .iter()
        .filter(|(_, app)| app.library_icon)
        .map(|(id, _)| *id)
        .collect();
    writers::icons::apply(
        &steam_dir,
        &icon_ids,
        &data_home().join("icons"),
        &data_dirs(),
    );

    if let Err(e) = record.save(&record_path) {
        log(format!("prior.json: {e}"));
        failed.push("prior.json".into());
    }
    if !failed.is_empty() {
        notify(&state, &format!("could not update {}", failed.join(", ")));
        std::process::exit(1);
    }
}
