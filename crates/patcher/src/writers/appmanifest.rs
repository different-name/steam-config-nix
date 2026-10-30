use std::collections::BTreeSet;
use std::path::Path;

use crate::log;
use crate::managed::Managed;
use crate::record::Record;
use crate::state::State;
use crate::steam::find_app_manifest;
use crate::writers::{Delta, Outcome, read_tree, text_outcome};

pub fn file_id(app_id: u32) -> String {
    format!("appmanifest:{app_id}")
}

pub fn ids(state: &State, record: &Record) -> Vec<u32> {
    let mut ids: BTreeSet<u32> = state
        .apps
        .iter()
        .filter(|(_, app)| !app.manifest_settings().is_empty())
        .map(|(id, _)| *id)
        .collect();
    ids.extend(record.appmanifest_ids());
    ids.into_iter().collect()
}

pub fn prepare(
    state: &State,
    steam_dir: &Path,
    app_id: u32,
    record: &Record,
) -> Result<Option<Outcome>, String> {
    let settings = state
        .apps
        .get(&app_id)
        .map(|app| app.manifest_settings())
        .unwrap_or_default();
    let Some(path) = find_app_manifest(steam_dir, app_id) else {
        if !settings.is_empty() {
            let keys: Vec<&str> = settings.iter().map(|(p, _)| *p.last().unwrap()).collect();
            log(format!(
                "{app_id} is not installed, {} not applied",
                keys.join(", ")
            ));
        }
        return Ok(None);
    };
    let Some((original, mut tree)) = read_tree(&path)? else {
        return Ok(None);
    };
    let file = file_id(app_id);
    let prev = record.keys_for(&file);
    let mut managed = Managed::new(&file, &prev);
    for (key_path, value) in &settings {
        managed.set_leaf(&mut tree, key_path, value);
    }
    managed.revert(&mut tree);
    let entries = managed.finish();
    let delta = Delta::Keys(file, entries);
    Ok(Some(text_outcome(
        &format!("appmanifest_{app_id}.acf"),
        &path,
        &original,
        &tree,
        delta,
    )))
}

#[cfg(test)]
mod tests {
    use super::{ids, prepare};
    use crate::record::Record;
    use crate::writers::testing::{state, temp, write};
    use std::fs;
    use std::path::PathBuf;
    use steam_config_vdf::text::parse;

    const MANIFEST: &str = "\"AppState\"\n{\n\t\"appid\"\t\t\"1091500\"\n\t\"name\"\t\t\"Cyberpunk 2077\"\n\t\"StateFlags\"\t\t\"4\"\n\t\"UserConfig\"\n\t{\n\t\t\"language\"\t\t\"english\"\n\t}\n}\n";

    fn value(text: &str, path: &[&str]) -> Option<String> {
        parse(text)
            .unwrap()
            .find_path(path)
            .and_then(|n| n.value.clone())
    }

    fn apply(steam: &PathBuf, extra: &str, record: &mut Record) -> bool {
        let st = state(extra);
        let mut wrote = false;
        for id in ids(&st, record) {
            if let Some(outcome) = prepare(&st, steam, id, record).unwrap() {
                if let Some(bytes) = &outcome.bytes {
                    fs::write(&outcome.path, bytes).unwrap();
                    wrote = true;
                }
                record.apply(outcome.delta);
            }
        }
        wrote
    }

    #[test]
    fn settings_written_then_restored() {
        let steam = temp("manifest-write");
        let path = steam.join("steamapps/appmanifest_1091500.acf");
        write(&path, MANIFEST);
        let extra = r#""apps": {"1091500": {"beta": "prerelease", "language": "german", "updateBehavior": 1, "backgroundDownloads": 2}}"#;
        let mut record = Record::default();
        assert!(apply(&steam, extra, &mut record));
        let text = fs::read_to_string(&path).unwrap();
        assert_eq!(
            value(&text, &["AppState", "UserConfig", "BetaKey"]).as_deref(),
            Some("prerelease")
        );
        assert_eq!(
            value(&text, &["AppState", "UserConfig", "language"]).as_deref(),
            Some("german")
        );
        assert_eq!(
            value(&text, &["AppState", "AutoUpdateBehavior"]).as_deref(),
            Some("1")
        );
        assert_eq!(
            value(&text, &["AppState", "AllowOtherDownloadsWhileRunning"]).as_deref(),
            Some("2")
        );
        assert_eq!(record.keys.len(), 4);
        assert!(record.keys.iter().all(|k| k.file == "appmanifest:1091500"));
        assert!(!apply(&steam, extra, &mut record));
        assert_eq!(ids(&state(""), &record), vec![1091500]);
        assert!(apply(&steam, "", &mut record));
        assert_eq!(fs::read_to_string(&path).unwrap(), MANIFEST);
        assert!(record.keys.is_empty());
    }

    #[test]
    fn a_beta_the_user_changed_is_kept() {
        let steam = temp("manifest-user");
        let path = steam.join("steamapps/appmanifest_1091500.acf");
        write(&path, MANIFEST);
        let mut record = Record::default();
        apply(
            &steam,
            r#""apps": {"1091500": {"beta": "prerelease"}}"#,
            &mut record,
        );
        let text = fs::read_to_string(&path)
            .unwrap()
            .replace("prerelease", "userbeta");
        fs::write(&path, text).unwrap();
        apply(&steam, "", &mut record);
        assert_eq!(
            value(
                &fs::read_to_string(&path).unwrap(),
                &["AppState", "UserConfig", "BetaKey"]
            )
            .as_deref(),
            Some("userbeta")
        );
    }

    #[test]
    fn uninstalled_app_keeps_its_record() {
        let steam = temp("manifest-uninstalled");
        fs::create_dir_all(steam.join("steamapps")).unwrap();
        let st = state(r#""apps": {"1091500": {"beta": "prerelease"}}"#);
        let mut record = Record::default();
        record.keys.push(crate::record::KeyEntry {
            file: "appmanifest:1091500".into(),
            path: vec!["AppState".into(), "UserConfig".into(), "BetaKey".into()],
            guard: vec![],
            ours: "prerelease".into(),
            prior: serde_json::Value::Null,
        });
        assert!(prepare(&st, &steam, 1091500, &record).unwrap().is_none());
        assert_eq!(ids(&state(""), &record), vec![1091500]);
    }
}
