use std::collections::BTreeSet;
use std::ffi::{CString, OsString};
use std::fs;
use std::os::unix::ffi::OsStrExt;
use std::path::{Path, PathBuf};

use crate::fsutil;
use crate::spec::Location;

fn parent(target: &str) -> &str {
    target.rsplit_once('/').map(|(p, _)| p).unwrap_or("")
}

pub fn mount_points<'a>(targets: impl Iterator<Item = &'a str>) -> Vec<String> {
    let parents: BTreeSet<String> = targets.map(|t| parent(t).to_string()).collect();
    parents
        .iter()
        .filter(|p| !parents.contains("") || p.is_empty())
        .filter(|p| !fsutil::ancestors(p).any(|a| parents.contains(a)))
        .cloned()
        .collect()
}

fn under(path: &str, dir: &str) -> bool {
    dir.is_empty() || path == dir || path.starts_with(&format!("{dir}/"))
}

fn join(base: &Path, rel: &str) -> PathBuf {
    if rel.is_empty() {
        base.to_path_buf()
    } else {
        base.join(rel)
    }
}

fn whiteout(path: &Path) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| format!("{}: {e}", parent.display()))?;
    }
    let cpath = CString::new(path.as_os_str().as_bytes()).map_err(|e| e.to_string())?;
    let rc = unsafe { libc::mknod(cpath.as_ptr(), libc::S_IFCHR | 0o600, 0) };
    if rc != 0 {
        return Err(format!(
            "{}: {}",
            path.display(),
            std::io::Error::last_os_error()
        ));
    }
    Ok(())
}

pub struct Plan {
    pub args: Vec<OsString>,
}

impl Plan {
    fn push(&mut self, parts: &[&dyn AsRef<std::ffi::OsStr>]) {
        for p in parts {
            self.args.push(p.as_ref().to_os_string());
        }
    }
}

pub struct Dirs<'a> {
    pub root: &'a Path,
    pub layer: Option<&'a Path>,
    pub hide: &'a Path,
    pub upper: &'a Path,
    pub work: &'a Path,
}

pub fn compose(plan: &mut Plan, location: &Location, dirs: &Dirs) -> Result<(), String> {
    let _ = fsutil::remove_any(dirs.hide);
    for target in &location.hide {
        whiteout(&dirs.hide.join(target))?;
    }
    for point in mount_points(location.declared()) {
        let real = join(dirs.root, &point);
        // a lower has to exist, and an empty directory is what the game would create there anyway
        if !real.is_dir() {
            fs::create_dir_all(&real).map_err(|e| format!("{}: {e}", real.display()))?;
            crate::log(format!("created {}", real.display()));
        }
        plan.push(&[&"--overlay-src", &real]);
        if let Some(layer) = dirs.layer.map(|l| join(l, &point)).filter(|l| l.exists()) {
            plan.push(&[&"--overlay-src", &layer]);
        }
        if location.hide.iter().any(|h| under(h, &point)) {
            plan.push(&[&"--overlay-src", &join(dirs.hide, &point)]);
        }
        let upper = join(dirs.upper, &point);
        let work = join(dirs.work, &point);
        for dir in [&upper, &work] {
            fs::create_dir_all(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
        }
        plan.push(&[&"--overlay", &upper, &work, &real]);
    }
    for entry in location.overlay.iter().filter(|o| o.read_only) {
        let layer = dirs.layer.ok_or("readOnly entry without a layer")?;
        plan.push(&[
            &"--ro-bind",
            &layer.join(&entry.target),
            &dirs.root.join(&entry.target),
        ]);
    }
    for dir in &location.passthrough {
        let real = dirs.root.join(dir);
        if !real.is_dir() {
            fs::create_dir_all(&real).map_err(|e| format!("{}: {e}", real.display()))?;
            crate::log(format!("created passthrough directory {}", real.display()));
        }
        plan.push(&[&"--bind", &real, &real]);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn points(targets: &[&str]) -> Vec<String> {
        mount_points(targets.iter().copied())
    }

    #[test]
    fn root_level_target_collapses_everything() {
        assert_eq!(points(&["winhttp.dll", "BepInEx/core", "a/b/c"]), vec![""]);
    }

    #[test]
    fn nested_parents_collapse_to_the_outermost() {
        assert_eq!(
            points(&["BepInEx/core", "BepInEx/plugins/x.dll", "Content/ui.png"]),
            vec!["BepInEx", "Content"]
        );
    }

    #[test]
    fn a_target_inside_a_sibling_target_shares_its_mount() {
        assert_eq!(
            points(&["Retail/sdk.dll", "Retail/mods/a.dll"]),
            vec!["Retail"]
        );
    }
}
