use std::collections::BTreeMap;
use std::path::PathBuf;

use serde::Deserialize;
use serde_json::Value;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Spec {
    pub key: String,
    pub name: String,
    pub app_id: Option<u64>,
    pub bwrap: PathBuf,
    pub notify_send: Option<PathBuf>,
    #[serde(default)]
    pub locations: BTreeMap<String, Location>,
}

#[derive(Deserialize, Default)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Location {
    pub layer: Option<PathBuf>,
    #[serde(default)]
    pub overlay: Vec<Overlay>,
    #[serde(default)]
    pub hide: Vec<String>,
    #[serde(default)]
    pub passthrough: Vec<String>,
    #[serde(default)]
    pub write_default: Vec<WriteDefault>,
    #[serde(default)]
    pub write_keys: Vec<WriteKeys>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Overlay {
    pub target: String,
    #[serde(default)]
    pub read_only: bool,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WriteDefault {
    pub target: String,
    pub source: PathBuf,
    pub executable: Option<bool>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WriteKeys {
    pub target: String,
    pub format: String,
    pub content: Value,
    #[serde(default)]
    pub create_if_missing: bool,
}

impl Location {
    pub fn mounted(&self) -> bool {
        !self.overlay.is_empty() || !self.hide.is_empty() || !self.passthrough.is_empty()
    }

    pub fn declared(&self) -> impl Iterator<Item = &str> {
        self.overlay
            .iter()
            .map(|o| o.target.as_str())
            .chain(self.hide.iter().map(String::as_str))
    }
}

pub fn load(path: &std::path::Path) -> Result<Spec, String> {
    let text = std::fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))?;
    serde_json::from_str(&text).map_err(|e| format!("{}: {e}", path.display()))
}
