use std::fs;
use std::io;
use std::os::unix::fs::{MetadataExt, PermissionsExt};
use std::path::Path;

pub fn exists(path: &Path) -> bool {
    fs::symlink_metadata(path).is_ok()
}

pub fn remove_any(path: &Path) -> io::Result<()> {
    match fs::symlink_metadata(path) {
        Ok(meta) if meta.is_dir() => fs::remove_dir_all(path),
        Ok(_) => fs::remove_file(path),
        Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(e),
    }
}

// the layer is served beneath the game's writes, so every copy is owned by the user and writable
pub fn copy_tree(src: &Path, dst: &Path, mode: Option<u32>) -> io::Result<()> {
    let meta = fs::symlink_metadata(src)?;
    if meta.file_type().is_symlink() {
        let link = fs::read_link(src)?;
        std::os::unix::fs::symlink(link, dst)?;
    } else if meta.is_dir() {
        fs::create_dir(dst)?;
        fs::set_permissions(dst, fs::Permissions::from_mode(0o755))?;
        for entry in fs::read_dir(src)? {
            let entry = entry?;
            copy_tree(&entry.path(), &dst.join(entry.file_name()), mode)?;
        }
    } else {
        fs::copy(src, dst)?;
        let mode = mode.unwrap_or(if meta.mode() & 0o111 != 0 {
            0o755
        } else {
            0o644
        });
        fs::set_permissions(dst, fs::Permissions::from_mode(mode))?;
    }
    Ok(())
}

pub fn walk(dir: &Path, f: &mut dyn FnMut(&Path, &fs::Metadata)) -> io::Result<()> {
    for entry in fs::read_dir(dir)? {
        let entry = entry?;
        let path = entry.path();
        let meta = fs::symlink_metadata(&path)?;
        if meta.is_dir() {
            walk(&path, f)?;
        }
        f(&path, &meta);
    }
    Ok(())
}

pub fn relative<'a>(path: &'a Path, base: &Path) -> &'a str {
    path.strip_prefix(base)
        .ok()
        .and_then(|p| p.to_str())
        .unwrap_or("")
}

pub fn ancestors(target: &str) -> impl Iterator<Item = &str> {
    target.match_indices('/').map(move |(i, _)| &target[..i])
}
