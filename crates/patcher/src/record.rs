use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::fileio::write_atomic;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct KeyEntry {
    pub file: String,
    pub path: Vec<String>,
    pub guard: Vec<String>,
    pub ours: String,
    pub prior: Value,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Record {
    pub version: u32,
    pub keys: Vec<KeyEntry>,
    pub shortcuts: BTreeMap<String, Vec<u32>>,
    pub grid: BTreeMap<String, BTreeMap<String, String>>,
    pub library_folders: Vec<String>,
}

impl Default for Record {
    fn default() -> Self {
        Record {
            version: 1,
            keys: Vec::new(),
            shortcuts: BTreeMap::new(),
            grid: BTreeMap::new(),
            library_folders: Vec::new(),
        }
    }
}

impl Record {
    pub fn load(path: &Path) -> Result<Record, String> {
        let text = match fs::read_to_string(path) {
            Ok(text) => text,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(Record::default()),
            Err(e) => return Err(e.to_string()),
        };
        let record: Record = serde_json::from_str(&text).map_err(|e| e.to_string())?;
        if record.version != 1 {
            return Err(format!("unknown version {}", record.version));
        }
        Ok(record)
    }

    pub fn save(&self, path: &Path) -> Result<(), String> {
        let text = serde_json::to_string_pretty(self).map_err(|e| e.to_string())?;
        write_atomic(path, text.as_bytes()).map_err(|e| e.to_string())
    }

    pub fn keys_for(&self, file: &str) -> Vec<KeyEntry> {
        self.keys
            .iter()
            .filter(|k| k.file == file)
            .cloned()
            .collect()
    }

    pub fn replace_keys(&mut self, file: &str, entries: Vec<KeyEntry>) {
        self.keys.retain(|k| k.file != file);
        self.keys.extend(entries);
    }

    pub fn shortcuts_for(&self, uid: u32) -> Vec<u32> {
        self.shortcuts
            .get(&uid.to_string())
            .cloned()
            .unwrap_or_default()
    }

    pub fn grid_for(&self, uid: u32) -> BTreeMap<String, String> {
        self.grid.get(&uid.to_string()).cloned().unwrap_or_default()
    }

    pub fn appmanifest_ids(&self) -> Vec<u32> {
        self.keys
            .iter()
            .filter_map(|k| k.file.strip_prefix("appmanifest:"))
            .filter_map(|id| id.parse().ok())
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::{KeyEntry, Record};
    use serde_json::{Value, json};
    use std::fs;

    fn entry(file: &str, last: &str) -> KeyEntry {
        KeyEntry {
            file: file.into(),
            path: vec!["Root".into(), last.into()],
            guard: Vec::new(),
            ours: "1".into(),
            prior: Value::Null,
        }
    }

    #[test]
    fn round_trips_through_json() {
        let dir = std::env::temp_dir().join(format!("scn-record-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("prior.json");
        assert_eq!(Record::load(&path).unwrap(), Record::default());
        let mut record = Record::default();
        record.keys.push(KeyEntry {
            file: "config".into(),
            path: vec![
                "InstallConfigStore".into(),
                "Accessibility".into(),
                "DesktopUIScale".into(),
            ],
            guard: Vec::new(),
            ours: "1.25".into(),
            prior: json!("1"),
        });
        record.keys.push(KeyEntry {
            file: "config".into(),
            path: vec!["CompatToolMapping".into(), "620".into()],
            guard: vec!["name".into()],
            ours: "tool".into(),
            prior: json!({"name": "user_tool"}),
        });
        record.shortcuts.insert("1".into(), vec![4132570534]);
        record.grid.insert(
            "1".into(),
            [("620p.png".to_string(), "/s".to_string())].into(),
        );
        record.library_folders.push("/mnt/games".into());
        record.save(&path).unwrap();
        let text = fs::read_to_string(&path).unwrap();
        assert!(text.contains("\"libraryFolders\""));
        assert!(text.contains("\"version\": 1"));
        assert_eq!(Record::load(&path).unwrap(), record);
        assert_eq!(record.shortcuts_for(1), vec![4132570534]);
        assert!(record.shortcuts_for(2).is_empty());
        assert_eq!(record.grid_for(1)["620p.png"], "/s");
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn bad_files_are_errors() {
        let dir = std::env::temp_dir().join(format!("scn-record-bad-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("prior.json");
        fs::write(&path, "{").unwrap();
        assert!(Record::load(&path).is_err());
        fs::write(
            &path,
            r#"{"version": 2, "keys": [], "shortcuts": {}, "grid": {}, "libraryFolders": []}"#,
        )
        .unwrap();
        assert!(Record::load(&path).unwrap_err().contains("version"));
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn keys_are_grouped_by_file() {
        let mut record = Record::default();
        record.keys = vec![
            entry("config", "a"),
            entry("appmanifest:620", "b"),
            entry("config", "c"),
        ];
        assert_eq!(record.keys_for("config").len(), 2);
        assert_eq!(record.appmanifest_ids(), vec![620]);
        record.replace_keys("config", vec![entry("config", "z")]);
        let names: Vec<&str> = record.keys.iter().map(|k| k.path[1].as_str()).collect();
        assert_eq!(names, vec!["b", "z"]);
    }
}
