pub mod appmanifest;
pub mod config_vdf;
pub mod grid;
pub mod icons;
pub mod libraryfolders;
pub mod localconfig;
pub mod shortcuts;

use std::fs;
use std::path::{Path, PathBuf};

use steam_config_vdf::text::{Node, dump, parse};

use crate::record::{KeyEntry, Record};

pub enum Delta {
    Keys(String, Vec<KeyEntry>),
    Shortcuts(u32, Vec<u32>),
    LibraryFolders(Vec<String>),
}

pub struct Outcome {
    pub description: String,
    pub path: PathBuf,
    pub bytes: Option<Vec<u8>>,
    pub delta: Delta,
    pub notes: Vec<String>,
}

impl Record {
    pub fn apply(&mut self, delta: Delta) {
        match delta {
            Delta::Keys(file, entries) => self.replace_keys(&file, entries),
            Delta::Shortcuts(uid, ids) => {
                self.shortcuts.insert(uid.to_string(), ids);
            }
            Delta::LibraryFolders(paths) => self.library_folders = paths,
        }
    }
}

pub fn read_tree(path: &Path) -> Result<Option<(String, Node)>, String> {
    let text = match fs::read_to_string(path) {
        Ok(text) => text,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(e) => return Err(e.to_string()),
    };
    let tree = parse(&text)?;
    Ok(Some((text, tree)))
}

pub fn text_outcome(
    description: &str,
    path: &Path,
    original: &str,
    tree: &Node,
    delta: Delta,
) -> Outcome {
    let text = dump(tree);
    Outcome {
        description: description.to_string(),
        path: path.to_path_buf(),
        bytes: (text != original).then(|| text.into_bytes()),
        delta,
        notes: Vec::new(),
    }
}

#[cfg(test)]
pub mod testing {
    use std::fs;
    use std::path::PathBuf;

    use crate::state::State;

    pub fn temp(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("scn-writers-{}-{name}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    pub fn state(extra: &str) -> State {
        let json = format!(
            r#"{{"onSteamRunning": "wait", "steam": "/bin/steam"{}{extra}}}"#,
            if extra.is_empty() { "" } else { ", " }
        );
        State::parse(&json).unwrap()
    }

    pub fn write(path: &PathBuf, text: &str) {
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, text).unwrap();
    }
}
