use std::collections::BTreeMap;
use std::fs;
use std::os::unix::fs::symlink;
use std::path::Path;

use crate::log;
use crate::state::State;

pub fn desired(state: &State) -> BTreeMap<String, String> {
    let mut files = BTreeMap::new();
    for (id, art) in state.artwork() {
        for (suffix, source) in art.slots() {
            let Some(source) = source else { continue };
            let ext = Path::new(source)
                .extension()
                .map(|e| format!(".{}", e.to_string_lossy()))
                .unwrap_or_default();
            files.insert(format!("{id}{suffix}{ext}"), source.to_string());
        }
    }
    files
}

fn links_to(path: &Path, target: &str) -> bool {
    fs::read_link(path).is_ok_and(|t| t.to_string_lossy() == target)
}

pub fn apply(
    grid_dir: &Path,
    desired: &BTreeMap<String, String>,
    previous: &BTreeMap<String, String>,
) -> BTreeMap<String, String> {
    let mut written = BTreeMap::new();
    for (name, target) in previous {
        if desired.contains_key(name) {
            continue;
        }
        let path = grid_dir.join(name);
        if links_to(&path, target) {
            if let Err(e) = fs::remove_file(&path) {
                log(format!("{}: {e}", path.display()));
                written.insert(name.clone(), target.clone());
            }
        }
    }
    if !desired.is_empty() {
        if let Err(e) = fs::create_dir_all(grid_dir) {
            log(format!("{}: {e}", grid_dir.display()));
            return previous.clone();
        }
    }
    for (name, source) in desired {
        let path = grid_dir.join(name);
        if !links_to(&path, source) {
            if fs::symlink_metadata(&path).is_ok() {
                if let Err(e) = fs::remove_file(&path) {
                    log(format!("{}: {e}", path.display()));
                    continue;
                }
            }
            if let Err(e) = symlink(source, &path) {
                log(format!("{}: {e}", path.display()));
                continue;
            }
        }
        written.insert(name.clone(), source.clone());
    }
    written
}

#[cfg(test)]
mod tests {
    use super::{apply, desired};
    use crate::writers::testing::{state, temp};
    use std::collections::BTreeMap;
    use std::fs;
    use std::os::unix::fs::{MetadataExt, PermissionsExt};
    use std::path::PathBuf;

    fn source(dir: &PathBuf, name: &str) -> String {
        let path = dir.join(name);
        fs::write(&path, b"image").unwrap();
        path.display().to_string()
    }

    fn map(entries: &[(&str, &str)]) -> BTreeMap<String, String> {
        entries
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect()
    }

    #[test]
    fn desired_maps_slots_and_extensions_for_both_kinds() {
        let st = state(
            r#""apps": {"438100": {"artwork": {"cover": "/a/c.jpg", "header": "/a/h.png", "hero": "/a/hero.jpg", "logo": "/a/logo.png"}}}, "shortcuts": {"7": {"name": "g", "exe": "/e", "dir": "/d", "artwork": {"hero": "/a/h"}}}"#,
        );
        let names: Vec<String> = desired(&st).keys().cloned().collect();
        assert_eq!(
            names,
            vec![
                "438100.png",
                "438100_hero.jpg",
                "438100_logo.png",
                "438100p.jpg",
                "7_hero"
            ]
        );
        assert!(desired(&state("")).is_empty());
    }

    #[test]
    fn creates_links_idempotently_and_updates_changed_sources() {
        let dir = temp("grid-links");
        let grid = dir.join("grid");
        let old = source(&dir, "old.jpg");
        let new = source(&dir, "new.jpg");
        let written = apply(&grid, &map(&[("438100p.jpg", &old)]), &BTreeMap::new());
        let link = grid.join("438100p.jpg");
        assert_eq!(fs::read_link(&link).unwrap().display().to_string(), old);
        assert_eq!(written, map(&[("438100p.jpg", &old)]));
        let ino = fs::symlink_metadata(&link).unwrap().ino();
        apply(&grid, &map(&[("438100p.jpg", &old)]), &written);
        assert_eq!(fs::symlink_metadata(&link).unwrap().ino(), ino);
        apply(&grid, &map(&[("438100p.jpg", &new)]), &written);
        assert_eq!(fs::read_link(&link).unwrap().display().to_string(), new);
    }

    #[test]
    fn cleanup_removes_our_link_and_keeps_a_user_file() {
        let dir = temp("grid-cleanup");
        let grid = dir.join("grid");
        let src = source(&dir, "hero.jpg");
        let written = apply(&grid, &map(&[("438100_hero.jpg", &src)]), &BTreeMap::new());
        assert!(apply(&grid, &BTreeMap::new(), &written).is_empty());
        assert!(fs::symlink_metadata(grid.join("438100_hero.jpg")).is_err());
        apply(&grid, &map(&[("438100_hero.jpg", &src)]), &BTreeMap::new());
        let link = grid.join("438100_hero.jpg");
        fs::remove_file(&link).unwrap();
        fs::write(&link, b"user art").unwrap();
        apply(&grid, &BTreeMap::new(), &written);
        assert_eq!(fs::read(&link).unwrap(), b"user art");
    }

    #[test]
    fn a_link_that_cannot_be_removed_stays_recorded() {
        let dir = temp("grid-stuck");
        let grid = dir.join("grid");
        let src = source(&dir, "hero.jpg");
        let written = apply(&grid, &map(&[("438100_hero.jpg", &src)]), &BTreeMap::new());
        fs::set_permissions(&grid, fs::Permissions::from_mode(0o555)).unwrap();
        let kept = apply(&grid, &BTreeMap::new(), &written);
        fs::set_permissions(&grid, fs::Permissions::from_mode(0o755)).unwrap();
        assert_eq!(kept, written);
        assert!(fs::symlink_metadata(grid.join("438100_hero.jpg")).is_ok());
        assert!(apply(&grid, &BTreeMap::new(), &kept).is_empty());
        assert!(fs::symlink_metadata(grid.join("438100_hero.jpg")).is_err());
    }

    #[test]
    fn a_manual_file_is_replaced_when_configured() {
        let dir = temp("grid-manual");
        let grid = dir.join("grid");
        fs::create_dir_all(&grid).unwrap();
        fs::write(grid.join("438100p.jpg"), b"manual").unwrap();
        let src = source(&dir, "cover.jpg");
        apply(&grid, &map(&[("438100p.jpg", &src)]), &BTreeMap::new());
        assert_eq!(
            fs::read_link(grid.join("438100p.jpg"))
                .unwrap()
                .display()
                .to_string(),
            src
        );
    }
}
