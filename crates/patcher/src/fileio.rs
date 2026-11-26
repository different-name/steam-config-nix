use std::fs;
use std::io::{self, Write};
use std::path::Path;

pub fn write_atomic(path: &Path, bytes: &[u8]) -> io::Result<()> {
    let dir = path.parent().unwrap_or(Path::new("."));
    let name = path
        .file_name()
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "path has no file name"))?;
    let tmp = dir.join(format!(".{}.scn-tmp", name.to_string_lossy()));
    let _ = fs::remove_file(&tmp);
    if let Err(e) = write_through(&tmp, path, bytes) {
        let _ = fs::remove_file(&tmp);
        return Err(e);
    }
    fs::File::open(dir)?.sync_all()?;
    Ok(())
}

fn write_through(tmp: &Path, path: &Path, bytes: &[u8]) -> io::Result<()> {
    let mut file = fs::File::create(tmp)?;
    if let Ok(meta) = fs::metadata(path) {
        file.set_permissions(meta.permissions())?;
    }
    file.write_all(bytes)?;
    file.sync_all()?;
    drop(file);
    fs::rename(tmp, path)
}

#[cfg(test)]
mod tests {
    use super::write_atomic;
    use std::fs;
    use std::os::unix::fs::PermissionsExt;

    #[test]
    fn writes_and_keeps_the_mode() {
        let dir = std::env::temp_dir().join(format!("scn-fileio-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("f.vdf");
        fs::write(&path, b"old").unwrap();
        fs::set_permissions(&path, fs::Permissions::from_mode(0o600)).unwrap();
        write_atomic(&path, b"new").unwrap();
        assert_eq!(fs::read(&path).unwrap(), b"new");
        assert_eq!(
            fs::metadata(&path).unwrap().permissions().mode() & 0o777,
            0o600
        );
        assert!(!dir.join(".f.vdf.scn-tmp").exists());
        write_atomic(&dir.join("fresh"), b"x").unwrap();
        assert_eq!(fs::read(dir.join("fresh")).unwrap(), b"x");
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn a_failed_write_leaves_no_temp_file() {
        let dir = std::env::temp_dir().join(format!("scn-fileio-fail-{}", std::process::id()));
        let target = dir.join("target");
        fs::create_dir_all(target.join("inner")).unwrap();
        assert!(write_atomic(&target, b"x").is_err());
        assert!(!dir.join(".target.scn-tmp").exists());
        fs::remove_dir_all(&dir).unwrap();
    }
}
