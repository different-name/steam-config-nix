use std::ffi::CString;
use std::fs;
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::{FileTypeExt, MetadataExt};
use std::path::{Path, PathBuf};

use crate::fsutil;

fn ctime(meta: &fs::Metadata) -> (i64, i64) {
    (meta.ctime(), meta.ctime_nsec())
}

fn remove_xattr(path: &Path, name: &str) -> bool {
    let Ok(cpath) = CString::new(path.as_os_str().as_bytes()) else {
        return false;
    };
    let Ok(cname) = CString::new(name) else {
        return false;
    };
    unsafe { libc::removexattr(cpath.as_ptr(), cname.as_ptr()) == 0 }
}

fn drop(upper: &Path, rel: &str, why: &str) -> Result<(), String> {
    let path = upper.join(rel);
    if fsutil::exists(&path) {
        fsutil::remove_any(&path).map_err(|e| format!("{}: {e}", path.display()))?;
        crate::log(format!("writes: {rel} {why}"));
    }
    Ok(())
}

// only the served files are reset, what the game put next to them stays
fn drop_served(upper: &Path, served: &Path, prefix: &str, why: &str) -> Result<(), String> {
    let mut files = Vec::new();
    fsutil::walk(served, &mut |path, meta| {
        if !meta.is_dir() {
            files.push(fsutil::relative(path, served).to_string());
        }
    })
    .map_err(|e| format!("{}: {e}", served.display()))?;
    for file in files {
        let rel = if prefix.is_empty() {
            file
        } else {
            format!("{prefix}/{file}")
        };
        drop(upper, &rel, why)?;
    }
    Ok(())
}

pub fn prepare(
    upper: &Path,
    root: &Path,
    declared: &[&str],
    layer: Option<&Path>,
    previous: &[PathBuf],
) -> Result<(), String> {
    fs::create_dir_all(upper).map_err(|e| format!("{}: {e}", upper.display()))?;
    for target in declared {
        let served = layer.map(|l| l.join(target));
        let copy_is_dir = fs::symlink_metadata(upper.join(target)).is_ok_and(|m| m.is_dir());
        match served {
            Some(dir) if dir.is_dir() && copy_is_dir => {
                drop_served(upper, &dir, target, "replaced by the declaration")?
            }
            _ => drop(upper, target, "replaced by the declaration")?,
        }
    }
    for old in previous {
        drop_served(upper, old, "", "no longer served")?;
    }
    let mut stale = Vec::new();
    let mut opaque = Vec::new();
    fsutil::walk(upper, &mut |path, meta| {
        let rel = fsutil::relative(path, upper).to_string();
        if meta.is_dir() {
            let user = remove_xattr(path, "user.overlay.opaque");
            let trusted = remove_xattr(path, "trusted.overlay.opaque");
            if user || trusted {
                opaque.push(rel);
            }
        } else if meta.is_file() || meta.file_type().is_char_device() {
            // steam can give an updated file an older mtime than the copy, but never an older ctime
            if fs::symlink_metadata(root.join(&rel)).is_ok_and(|real| ctime(&real) > ctime(meta)) {
                stale.push(rel);
            }
        }
    })
    .map_err(|e| format!("{}: {e}", upper.display()))?;
    for rel in stale {
        drop(upper, &rel, "dropped, the real file changed")?;
    }
    for rel in opaque {
        crate::log(format!("writes: {rel} no longer hides the real directory"));
    }
    Ok(())
}
