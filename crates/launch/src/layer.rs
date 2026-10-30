use std::fs;
use std::path::{Path, PathBuf};

use crate::fsutil;

fn hash(store_path: &Path) -> String {
    store_path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("layer")
        .chars()
        .take(32)
        .collect()
}

pub fn materialise(store_path: &Path, base: &Path) -> Result<PathBuf, String> {
    let dest = base.join(hash(store_path));
    if !dest.is_dir() {
        fs::create_dir_all(base).map_err(|e| format!("{}: {e}", base.display()))?;
        let tmp = base.join(format!("{}.tmp-{}", hash(store_path), std::process::id()));
        let _ = fsutil::remove_any(&tmp);
        fsutil::copy_tree(store_path, &tmp, None)
            .and_then(|_| fs::rename(&tmp, &dest))
            .map_err(|e| format!("materialising {}: {e}", store_path.display()))?;
        crate::log(format!("materialised layer {}", dest.display()));
    }
    Ok(dest)
}

pub fn previous(base: &Path, keep: Option<&Path>) -> Vec<PathBuf> {
    fs::read_dir(base)
        .map(|entries| {
            entries
                .flatten()
                .map(|e| e.path())
                .filter(|p| Some(p.as_path()) != keep && p.is_dir())
                .collect()
        })
        .unwrap_or_default()
}

pub fn sweep(base: &Path, keep: Option<&Path>) {
    for old in previous(base, keep) {
        let _ = fsutil::remove_any(&old);
    }
}
