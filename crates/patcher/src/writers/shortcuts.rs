use std::collections::BTreeSet;
use std::fs;
use std::path::Path;

use steam_config_vdf::binary::{Dict, DictExt, Value, dumps, loads};

use crate::record::Record;
use crate::state::{Shortcut, State};
use crate::writers::{Delta, Outcome};

fn quote(path: &str) -> String {
    if path.is_empty() {
        String::new()
    } else {
        format!("\"{path}\"")
    }
}

pub fn recursive_update(dest: &mut Dict, source: &Dict) -> bool {
    let mut modified = false;
    for (key, value) in source {
        match dest.iter().position(|(k, _)| k == key) {
            Some(i) => match (&mut dest[i].1, value) {
                (Value::Dict(d), Value::Dict(s)) => {
                    if recursive_update(d, s) {
                        modified = true;
                    }
                }
                (existing, _) => {
                    if existing != value {
                        *existing = value.clone();
                        modified = true;
                    }
                }
            },
            None => {
                dest.push((key.clone(), value.clone()));
                modified = true;
            }
        }
    }
    modified
}

fn entry_for(id: u32, shortcut: &Shortcut, new: bool) -> Dict {
    let mut entry: Dict = vec![
        ("appid".into(), Value::Int32(id)),
        ("AppName".into(), Value::Str(shortcut.name.clone())),
        ("Exe".into(), Value::Str(quote(&shortcut.exe))),
        ("StartDir".into(), Value::Str(quote(&shortcut.dir))),
        (
            "icon".into(),
            Value::Str(shortcut.icon.clone().unwrap_or_default()),
        ),
        ("LaunchOptions".into(), Value::Str(String::new())),
        ("AllowDesktopConfig".into(), Value::Int32(1)),
    ];
    if let Some(hidden) = shortcut.hidden {
        entry.push(("IsHidden".into(), Value::Int32(hidden as u32)));
    }
    if let Some(vr) = shortcut.vr {
        entry.push(("OpenVR".into(), Value::Int32(vr as u32)));
    }
    if new {
        entry.push(("tags".into(), Value::Dict(Dict::new())));
    }
    entry
}

fn appid_of(entry: &Value) -> Option<u32> {
    match entry {
        Value::Dict(d) => match d.get("appid") {
            Some(Value::Int32(id)) => Some(*id),
            _ => None,
        },
        _ => None,
    }
}

pub fn prepare(
    state: &State,
    steam_dir: &Path,
    uid: u32,
    record: &Record,
) -> Result<Option<Outcome>, String> {
    let path = steam_dir.join(format!("userdata/{uid}/config/shortcuts.vdf"));
    let recorded = record.shortcuts_for(uid);
    let original = match fs::read(&path) {
        Ok(bytes) => Some(bytes),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => None,
        Err(e) => return Err(e.to_string()),
    };
    if original.is_none() && state.shortcuts.is_empty() && recorded.is_empty() {
        return Ok(None);
    }
    let mut top = match &original {
        Some(bytes) => loads(bytes)?,
        None => Dict::new(),
    };
    if top.get("shortcuts").is_none() && !state.shortcuts.is_empty() {
        top.insert_or_replace("shortcuts", Value::Dict(Dict::new()));
    }
    let mut ours: BTreeSet<u32> = recorded
        .iter()
        .copied()
        .filter(|id| state.shortcuts.contains_key(id))
        .collect();
    match top.get_mut("shortcuts") {
        Some(Value::Dict(shortcuts)) => ours.extend(update(shortcuts, state, &recorded)),
        Some(_) => return Err("shortcuts is not a block".into()),
        None => {}
    }
    let bytes = dumps(&top)?;
    let changed = match &original {
        Some(orig) => *orig != bytes,
        None => !bytes.is_empty(),
    };
    Ok(Some(Outcome {
        description: format!("shortcuts.vdf (user {uid})"),
        path,
        bytes: changed.then_some(bytes),
        delta: Delta::Shortcuts(uid, ours.into_iter().collect()),
        notes: Vec::new(),
    }))
}

fn update(shortcuts: &mut Dict, state: &State, recorded: &[u32]) -> Vec<u32> {
    let mut inserted = Vec::new();
    let mut next_index = shortcuts
        .iter()
        .filter_map(|(k, _)| k.parse::<i64>().ok())
        .max()
        .unwrap_or(-1)
        + 1;
    for (id, shortcut) in &state.shortcuts {
        let existing = shortcuts
            .iter()
            .position(|(_, entry)| appid_of(entry) == Some(*id));
        match existing {
            Some(i) => {
                let Value::Dict(entry) = &mut shortcuts[i].1 else {
                    unreachable!()
                };
                recursive_update(entry, &entry_for(*id, shortcut, false));
            }
            None => {
                shortcuts.push((
                    next_index.to_string(),
                    Value::Dict(entry_for(*id, shortcut, true)),
                ));
                next_index += 1;
                inserted.push(*id);
            }
        }
    }
    let removed: Vec<u32> = recorded
        .iter()
        .copied()
        .filter(|id| !state.shortcuts.contains_key(id))
        .collect();
    shortcuts.retain(|(_, entry)| !appid_of(entry).is_some_and(|id| removed.contains(&id)));
    inserted
}

#[cfg(test)]
mod tests {
    use super::{prepare, recursive_update};
    use crate::record::Record;
    use crate::writers::testing::{state, temp};
    use std::fs;
    use std::path::PathBuf;
    use steam_config_vdf::binary::{Dict, DictExt, Value, dumps, loads};

    fn dict(entries: Vec<(&str, Value)>) -> Dict {
        entries
            .into_iter()
            .map(|(k, v)| (k.to_string(), v))
            .collect()
    }

    fn file(steam: &PathBuf) -> PathBuf {
        steam.join("userdata/1/config/shortcuts.vdf")
    }

    fn seed(steam: &PathBuf, ids: &[u32]) {
        let entries: Dict = ids
            .iter()
            .enumerate()
            .map(|(i, id)| {
                (
                    i.to_string(),
                    Value::Dict(dict(vec![("appid", Value::Int32(*id))])),
                )
            })
            .collect();
        fs::create_dir_all(file(steam).parent().unwrap()).unwrap();
        fs::write(
            file(steam),
            dumps(&dict(vec![("shortcuts", Value::Dict(entries))])).unwrap(),
        )
        .unwrap();
    }

    fn read(steam: &PathBuf) -> Dict {
        match loads(&fs::read(file(steam)).unwrap())
            .unwrap()
            .get("shortcuts")
        {
            Some(Value::Dict(d)) => d.clone(),
            other => panic!("{other:?}"),
        }
    }

    fn entry<'a>(shortcuts: &'a Dict, index: &str) -> &'a Dict {
        match shortcuts.get(index) {
            Some(Value::Dict(d)) => d,
            other => panic!("{index}: {other:?}"),
        }
    }

    fn apply(steam: &PathBuf, extra: &str, record: &mut Record) -> bool {
        let Some(outcome) = prepare(&state(extra), steam, 1, record).unwrap() else {
            return false;
        };
        let wrote = outcome.bytes.is_some();
        if let Some(bytes) = &outcome.bytes {
            fs::create_dir_all(outcome.path.parent().unwrap()).unwrap();
            fs::write(&outcome.path, bytes).unwrap();
        }
        record.apply(outcome.delta);
        wrote
    }

    const PROBE: &str = r#""shortcuts": {"4132570534": {"name": "probe", "exe": "/opt/probe/run", "dir": "/opt/probe", "vr": true, "hidden": true, "icon": "/i.png"}}"#;

    #[test]
    fn recursive_update_adds_changes_and_reports() {
        let mut dest = dict(vec![("shortcuts", Value::Dict(Dict::new()))]);
        assert!(recursive_update(
            &mut dest,
            &dict(vec![(
                "shortcuts",
                Value::Dict(dict(vec![(
                    "0",
                    Value::Dict(dict(vec![("appid", Value::Int32(1))]))
                )]))
            )])
        ));
        let mut dest = dict(vec![
            ("appid", Value::Int32(1)),
            ("AppName", Value::Str("Old".into())),
        ]);
        assert!(recursive_update(
            &mut dest,
            &dict(vec![("AppName", Value::Str("New".into()))])
        ));
        assert_eq!(dest.get("AppName"), Some(&Value::Str("New".into())));
        assert_eq!(dest.get("appid"), Some(&Value::Int32(1)));
        assert!(!recursive_update(
            &mut dest,
            &dict(vec![("appid", Value::Int32(1))])
        ));
    }

    #[test]
    fn new_shortcut_gets_the_next_index_and_all_fields() {
        let steam = temp("shortcuts-new");
        seed(&steam, &[555, 777]);
        let mut record = Record::default();
        assert!(apply(&steam, PROBE, &mut record));
        let shortcuts = read(&steam);
        let e = entry(&shortcuts, "2");
        assert_eq!(e.get("appid"), Some(&Value::Int32(4132570534)));
        assert_eq!(e.get("AppName"), Some(&Value::Str("probe".into())));
        assert_eq!(e.get("Exe"), Some(&Value::Str("\"/opt/probe/run\"".into())));
        assert_eq!(
            e.get("StartDir"),
            Some(&Value::Str("\"/opt/probe\"".into()))
        );
        assert_eq!(e.get("icon"), Some(&Value::Str("/i.png".into())));
        assert_eq!(e.get("LaunchOptions"), Some(&Value::Str(String::new())));
        assert_eq!(e.get("AllowDesktopConfig"), Some(&Value::Int32(1)));
        assert_eq!(e.get("IsHidden"), Some(&Value::Int32(1)));
        assert_eq!(e.get("OpenVR"), Some(&Value::Int32(1)));
        assert_eq!(e.get("tags"), Some(&Value::Dict(Dict::new())));
        assert!(e.get("AllowOverlay").is_none());
        assert_eq!(record.shortcuts_for(1), vec![4132570534]);
        assert!(!apply(&steam, PROBE, &mut record));
    }

    #[test]
    fn existing_entry_is_reused_and_steams_fields_survive() {
        let steam = temp("shortcuts-reuse");
        fs::create_dir_all(file(&steam).parent().unwrap()).unwrap();
        let existing = dict(vec![
            ("appid", Value::Int32(4132570534)),
            ("AppName", Value::Str("old".into())),
            ("LastPlayTime", Value::Int32(99)),
            (
                "tags",
                Value::Dict(dict(vec![("0", Value::Str("favorite".into()))])),
            ),
        ]);
        fs::write(
            file(&steam),
            dumps(&dict(vec![(
                "shortcuts",
                Value::Dict(dict(vec![("3", Value::Dict(existing))])),
            )]))
            .unwrap(),
        )
        .unwrap();
        let mut record = Record::default();
        apply(&steam, PROBE, &mut record);
        let shortcuts = read(&steam);
        assert_eq!(shortcuts.len(), 1);
        let e = entry(&shortcuts, "3");
        assert_eq!(e.get("AppName"), Some(&Value::Str("probe".into())));
        assert_eq!(e.get("LastPlayTime"), Some(&Value::Int32(99)));
        assert_eq!(
            e.get("tags"),
            Some(&Value::Dict(dict(vec![(
                "0",
                Value::Str("favorite".into())
            )])))
        );
    }

    #[test]
    fn an_entry_steam_already_has_is_updated_but_never_removed() {
        let steam = temp("shortcuts-adopt");
        seed(&steam, &[4132570534, 777]);
        let mut record = Record::default();
        assert!(apply(&steam, PROBE, &mut record));
        assert_eq!(
            entry(&read(&steam), "0").get("AppName"),
            Some(&Value::Str("probe".into()))
        );
        assert!(record.shortcuts_for(1).is_empty());
        assert!(!apply(&steam, "", &mut record));
        assert_eq!(read(&steam).len(), 2);
    }

    #[test]
    fn empty_dir_and_icon_stay_empty() {
        let steam = temp("shortcuts-empty");
        let mut record = Record::default();
        apply(
            &steam,
            r#""shortcuts": {"5": {"name": "g", "exe": "", "dir": ""}}"#,
            &mut record,
        );
        let shortcuts = read(&steam);
        let e = entry(&shortcuts, "0");
        assert_eq!(e.get("Exe"), Some(&Value::Str(String::new())));
        assert_eq!(e.get("StartDir"), Some(&Value::Str(String::new())));
        assert_eq!(e.get("icon"), Some(&Value::Str(String::new())));
        assert!(e.get("IsHidden").is_none());
        assert!(e.get("OpenVR").is_none());
    }

    #[test]
    fn recorded_shortcuts_are_removed_and_others_kept() {
        let steam = temp("shortcuts-remove");
        seed(&steam, &[555, 777]);
        let mut record = Record::default();
        record.shortcuts.insert("1".into(), vec![555]);
        assert!(apply(&steam, "", &mut record));
        let shortcuts = read(&steam);
        assert_eq!(shortcuts.len(), 1);
        assert_eq!(
            entry(&shortcuts, "1").get("appid"),
            Some(&Value::Int32(777))
        );
        assert!(record.shortcuts_for(1).is_empty());
    }

    #[test]
    fn missing_file_behaviour() {
        let steam = temp("shortcuts-missing");
        let mut record = Record::default();
        assert!(prepare(&state(""), &steam, 1, &record).unwrap().is_none());
        record.shortcuts.insert("1".into(), vec![555]);
        let outcome = prepare(&state(""), &steam, 1, &record).unwrap().unwrap();
        assert!(outcome.bytes.is_none());
        record.apply(outcome.delta);
        assert!(record.shortcuts_for(1).is_empty());
        assert!(apply(&steam, PROBE, &mut record));
        assert_eq!(
            entry(&read(&steam), "0").get("appid"),
            Some(&Value::Int32(4132570534))
        );
    }
}
