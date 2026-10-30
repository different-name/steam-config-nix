use std::path::{Path, PathBuf};

use crate::formats::keyvalue;

fn canonical_dir(path: &Path) -> Option<PathBuf> {
    let real = std::fs::canonicalize(path).ok()?;
    real.is_dir().then_some(real)
}

fn steam_roots() -> Vec<PathBuf> {
    let home = std::env::var("HOME").unwrap_or_default();
    [
        "{home}/.steam/root",
        "{home}/.steam/steam",
        "{home}/.local/share/Steam",
    ]
    .iter()
    .map(|p| PathBuf::from(p.replace("{home}", &home)))
    .collect()
}

fn libraries(steam: &Path) -> Vec<PathBuf> {
    let file = ["steamapps/libraryfolders.vdf", "config/libraryfolders.vdf"]
        .iter()
        .map(|p| steam.join(p))
        .find(|p| p.is_file());
    let Some(file) = file else { return Vec::new() };
    let Ok(text) = std::fs::read_to_string(&file) else {
        return Vec::new();
    };
    let Ok(root) = keyvalue::parse(&text) else {
        return Vec::new();
    };
    let Some(folders) = root.find("libraryfolders") else {
        return Vec::new();
    };
    folders
        .children()
        .filter_map(|entry| entry.find("path"))
        .filter_map(|p| p.value.clone())
        .map(PathBuf::from)
        .collect()
}

fn install_dir(manifest: &Path) -> Option<String> {
    let text = std::fs::read_to_string(manifest).ok()?;
    let root = keyvalue::parse(&text).ok()?;
    root.find("AppState")?.find("installdir")?.value.clone()
}

pub fn game(app_id: Option<u64>) -> Option<PathBuf> {
    if let Ok(path) = std::env::var("STEAM_COMPAT_INSTALL_PATH") {
        if let Some(real) = canonical_dir(Path::new(&path)) {
            return Some(real);
        }
    }
    let app_id = app_id?;
    for steam in steam_roots() {
        for library in libraries(&steam) {
            let manifest = library.join(format!("steamapps/appmanifest_{app_id}.acf"));
            let Some(dir) = install_dir(&manifest) else {
                continue;
            };
            if let Some(real) = canonical_dir(&library.join("steamapps/common").join(dir)) {
                return Some(real);
            }
        }
    }
    None
}

fn compat_data_in(steams: &[PathBuf], app_id: u64) -> Option<PathBuf> {
    steams
        .iter()
        .flat_map(|steam| libraries(steam))
        .map(|library| library.join(format!("steamapps/compatdata/{app_id}")))
        .find(|dir| dir.is_dir())
}

pub fn compat_data(app_id: u64) -> Option<PathBuf> {
    compat_data_in(&steam_roots(), app_id)
}

pub fn prefix() -> Option<PathBuf> {
    let data = std::env::var("STEAM_COMPAT_DATA_PATH").ok()?;
    canonical_dir(&Path::new(&data).join("pfx"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn compat_data_by_library() {
        let root = std::env::temp_dir().join(format!("scn-compat-{}", std::process::id()));
        let steam = root.join("steam");
        let lib = root.join("lib");
        std::fs::create_dir_all(steam.join("steamapps")).unwrap();
        std::fs::create_dir_all(lib.join("steamapps/compatdata/620")).unwrap();
        std::fs::write(
            steam.join("steamapps/libraryfolders.vdf"),
            format!(
                "\"libraryfolders\"\n{{\n\"0\"\n{{\n\"path\" \"{}\"\n}}\n\"1\"\n{{\n\"path\" \"{}\"\n}}\n}}\n",
                steam.display(),
                lib.display()
            ),
        )
        .unwrap();
        let steams = [steam.clone()];
        assert_eq!(
            compat_data_in(&steams, 620),
            Some(lib.join("steamapps/compatdata/620"))
        );
        assert_eq!(compat_data_in(&steams, 440), None);
        let _ = std::fs::remove_dir_all(&root);
    }
}
