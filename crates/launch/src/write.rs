use std::fs;
use std::path::Path;

use crate::formats;
use crate::fsutil;
use crate::spec::Location;

pub fn apply(location: &Location, name: &str, root: &Path, originals: &Path) -> Vec<String> {
    let mut failures = Vec::new();
    for entry in &location.write_default {
        let dest = root.join(&entry.target);
        if fsutil::exists(&dest) {
            continue;
        }
        let mode = entry.executable.map(|x| if x { 0o755 } else { 0o644 });
        let done = dest
            .parent()
            .map(fs::create_dir_all)
            .unwrap_or(Ok(()))
            .and_then(|_| fsutil::copy_tree(&entry.source, &dest, mode));
        match done {
            Ok(()) => crate::log(format!("{name}/{}: written", entry.target)),
            Err(e) => failures.push(format!("{name}/{}: {e}", entry.target)),
        }
    }
    for entry in &location.write_keys {
        let dest = root.join(&entry.target);
        let existing = match fs::read(&dest) {
            Ok(bytes) => Some(bytes),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => None,
            Err(e) => {
                failures.push(format!("{name}/{}: {e}", entry.target));
                continue;
            }
        };
        if existing.is_none() && !entry.create_if_missing {
            crate::log(format!("{name}/{}: not there yet, skipped", entry.target));
            continue;
        }
        let original = originals.join(&entry.target);
        if let Some(bytes) = &existing {
            if !fsutil::exists(&original) {
                let tmp = original.with_extension("scn-tmp");
                let kept = original
                    .parent()
                    .map(fs::create_dir_all)
                    .unwrap_or(Ok(()))
                    .and_then(|_| fs::write(&tmp, bytes))
                    .and_then(|_| fs::rename(&tmp, &original));
                if let Err(e) = kept {
                    failures.push(format!(
                        "{name}/{}: keeping the original: {e}",
                        entry.target
                    ));
                    continue;
                }
            }
        }
        let before = existing.unwrap_or_default();
        let after = match formats::apply(&entry.format, &entry.content, &before) {
            Ok(bytes) => bytes,
            Err(e) => {
                failures.push(format!("{name}/{}: {e}", entry.target));
                continue;
            }
        };
        if after == before {
            continue;
        }
        let tmp = dest.with_extension("scn-tmp");
        let written = dest
            .parent()
            .map(fs::create_dir_all)
            .unwrap_or(Ok(()))
            .and_then(|_| fs::write(&tmp, &after))
            .and_then(|_| fs::rename(&tmp, &dest));
        match written {
            Ok(()) => crate::log(format!("{name}/{}: keys set", entry.target)),
            Err(e) => failures.push(format!("{name}/{}: {e}", entry.target)),
        }
    }
    failures
}
