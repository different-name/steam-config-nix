use std::path::Path;

use crate::log;
use crate::managed::Managed;
use crate::record::Record;
use crate::state::State;
use crate::writers::{Delta, Outcome, read_tree, text_outcome};

const ROOT: &str = "UserLocalConfigStore";
const LEGACY_LAUNCH: &str = "steam-config-nix/apps/";

pub fn file_id(uid: u32) -> String {
    format!("localconfig:{uid}")
}

pub fn prepare(
    state: &State,
    steam_dir: &Path,
    uid: u32,
    record: &Record,
) -> Result<Option<Outcome>, String> {
    let path = steam_dir.join(format!("userdata/{uid}/config/localconfig.vdf"));
    let Some((original, mut tree)) = read_tree(&path)? else {
        log(format!("localconfig.vdf for user {uid} is missing"));
        return Ok(None);
    };
    let file = file_id(uid);
    let prev = record.keys_for(&file);
    let mut managed = Managed::new(&file, &prev);
    if let Some(bits) = state.display_rates_as_bits {
        managed.set_leaf(
            &mut tree,
            &[ROOT, "system", "displayratesasbits"],
            if bits { "1" } else { "0" },
        );
    }
    let mut per_app: Vec<(String, Option<bool>, Option<u8>)> = state
        .apps
        .iter()
        .map(|(id, app)| (id.to_string(), app.overlay, app.steam_input))
        .collect();
    per_app.extend(
        state
            .shortcuts
            .iter()
            .map(|(id, s)| (id.to_string(), s.overlay, None)),
    );
    for (id, overlay, steam_input) in &per_app {
        if let Some(overlay) = overlay {
            managed.set_leaf(
                &mut tree,
                &[ROOT, "apps", id, "OverlayAppEnable"],
                if *overlay { "1" } else { "0" },
            );
        }
        if let Some(input) = steam_input {
            managed.set_leaf(
                &mut tree,
                &[ROOT, "apps", id, "UseSteamControllerConfig"],
                &input.to_string(),
            );
        }
    }
    managed.revert(&mut tree);
    let mut notes = Vec::new();
    for id in state.apps.keys() {
        let id = id.to_string();
        let path = [
            ROOT,
            "Software",
            "Valve",
            "Steam",
            "apps",
            &id,
            "LaunchOptions",
        ];
        if let Some(node) = tree.find_path_mut(&path) {
            if node.children.is_none()
                && node
                    .value
                    .as_deref()
                    .is_some_and(|v| v.contains(LEGACY_LAUNCH))
            {
                node.value = Some(String::new());
                notes.push(format!(
                    "cleared the launch options the previous version set for {id}"
                ));
            }
        }
    }
    let entries = managed.finish();
    let delta = Delta::Keys(file, entries);
    let mut outcome = text_outcome(
        &format!("localconfig.vdf (user {uid})"),
        &path,
        &original,
        &tree,
        delta,
    );
    outcome.notes = notes;
    Ok(Some(outcome))
}

#[cfg(test)]
mod tests {
    use super::prepare;
    use crate::record::Record;
    use crate::writers::testing::{state, temp, write};
    use std::fs;
    use std::path::PathBuf;
    use steam_config_vdf::text::parse;

    const LOCALCONFIG: &str = "\"UserLocalConfigStore\"\n{\n\t\"Software\"\n\t{\n\t\t\"Valve\"\n\t\t{\n\t\t\t\"Steam\"\n\t\t\t{\n\t\t\t\t\"apps\"\n\t\t\t\t{\n\t\t\t\t\t\"620\"\n\t\t\t\t\t{\n\t\t\t\t\t\t\"LaunchOptions\"\t\t\"/bin/sh -c x /var/lib/steam-config-nix/apps/620/wrapper %command%\"\n\t\t\t\t\t}\n\t\t\t\t\t\"630\"\n\t\t\t\t\t{\n\t\t\t\t\t\t\"LaunchOptions\"\t\t\"-novid\"\n\t\t\t\t\t}\n\t\t\t\t}\n\t\t\t}\n\t\t}\n\t}\n\t\"system\"\n\t{\n\t\t\"displayratesasbits\"\t\t\"0\"\n\t}\n}\n";

    fn value(text: &str, path: &[&str]) -> Option<String> {
        parse(text)
            .unwrap()
            .find_path(path)
            .and_then(|n| n.value.clone())
    }

    fn apply(steam: &PathBuf, extra: &str, record: &mut Record) -> bool {
        apply_noting(steam, extra, record).0
    }

    fn apply_noting(steam: &PathBuf, extra: &str, record: &mut Record) -> (bool, Vec<String>) {
        let outcome = prepare(&state(extra), steam, 1, record).unwrap().unwrap();
        let wrote = outcome.bytes.is_some();
        if let Some(bytes) = &outcome.bytes {
            fs::write(&outcome.path, bytes).unwrap();
        }
        record.apply(outcome.delta);
        (wrote, outcome.notes)
    }

    #[test]
    fn writes_overlay_input_and_rates_for_apps_and_shortcuts() {
        let steam = temp("localconfig-write");
        let path = steam.join("userdata/1/config/localconfig.vdf");
        write(&path, LOCALCONFIG);
        let extra = r#""displayRatesAsBits": true, "apps": {"620": {"overlay": false, "steamInput": 2}, "630": {}}, "shortcuts": {"4132570534": {"name": "p", "exe": "/e", "dir": "/d", "overlay": false}}"#;
        let mut record = Record::default();
        assert!(apply(&steam, extra, &mut record));
        let text = fs::read_to_string(&path).unwrap();
        assert_eq!(
            value(
                &text,
                &["UserLocalConfigStore", "system", "displayratesasbits"]
            )
            .as_deref(),
            Some("1")
        );
        assert_eq!(
            value(
                &text,
                &["UserLocalConfigStore", "apps", "620", "OverlayAppEnable"]
            )
            .as_deref(),
            Some("0")
        );
        assert_eq!(
            value(
                &text,
                &[
                    "UserLocalConfigStore",
                    "apps",
                    "620",
                    "UseSteamControllerConfig"
                ]
            )
            .as_deref(),
            Some("2")
        );
        assert_eq!(
            value(
                &text,
                &[
                    "UserLocalConfigStore",
                    "apps",
                    "4132570534",
                    "OverlayAppEnable"
                ]
            )
            .as_deref(),
            Some("0")
        );
        assert_eq!(
            value(
                &text,
                &[
                    "UserLocalConfigStore",
                    "Software",
                    "Valve",
                    "Steam",
                    "apps",
                    "620",
                    "LaunchOptions"
                ]
            )
            .as_deref(),
            Some("")
        );
        assert_eq!(
            value(
                &text,
                &[
                    "UserLocalConfigStore",
                    "Software",
                    "Valve",
                    "Steam",
                    "apps",
                    "630",
                    "LaunchOptions"
                ]
            )
            .as_deref(),
            Some("-novid")
        );
        assert_eq!(record.keys.len(), 4);
        assert!(record.keys.iter().all(|k| k.file == "localconfig:1"));
        assert!(!apply(&steam, extra, &mut record));
        apply(&steam, "", &mut record);
        assert!(record.keys.is_empty());
        let text = fs::read_to_string(&path).unwrap();
        assert_eq!(
            value(
                &text,
                &["UserLocalConfigStore", "system", "displayratesasbits"]
            )
            .as_deref(),
            Some("0")
        );
        assert!(
            value(
                &text,
                &["UserLocalConfigStore", "apps", "620", "OverlayAppEnable"]
            )
            .is_none()
        );
        assert!(
            value(
                &text,
                &[
                    "UserLocalConfigStore",
                    "apps",
                    "4132570534",
                    "OverlayAppEnable"
                ]
            )
            .is_none()
        );
    }

    #[test]
    fn legacy_launch_options_are_cleared_only_for_configured_apps() {
        let steam = temp("localconfig-legacy");
        let path = steam.join("userdata/1/config/localconfig.vdf");
        write(&path, LOCALCONFIG);
        let mut record = Record::default();
        assert_eq!(apply_noting(&steam, "", &mut record), (false, vec![]));
        let (wrote, notes) = apply_noting(&steam, r#""apps": {"620": {}}"#, &mut record);
        assert!(wrote);
        assert_eq!(notes.len(), 1);
        assert!(notes[0].contains("620"));
        assert!(record.keys.is_empty());
        let text = fs::read_to_string(&path).unwrap();
        assert_eq!(
            value(
                &text,
                &[
                    "UserLocalConfigStore",
                    "Software",
                    "Valve",
                    "Steam",
                    "apps",
                    "620",
                    "LaunchOptions"
                ]
            )
            .as_deref(),
            Some("")
        );
    }

    #[test]
    fn missing_file_is_skipped() {
        let steam = temp("localconfig-missing");
        assert!(
            prepare(&state(""), &steam, 1, &Record::default())
                .unwrap()
                .is_none()
        );
    }
}
