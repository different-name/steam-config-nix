use std::path::Path;

use crate::compat;
use crate::log;
use crate::managed::Managed;
use crate::record::Record;
use crate::state::{CompatTool, State};
use crate::writers::{Delta, Outcome, read_tree, text_outcome};

pub const FILE: &str = "config";
const MAPPING: [&str; 5] = [
    "InstallConfigStore",
    "Software",
    "Valve",
    "Steam",
    "CompatToolMapping",
];
const SCALE: [&str; 3] = ["InstallConfigStore", "Accessibility", "DesktopUIScale"];

pub fn format_g18(v: f64) -> String {
    let sci = format!("{:.17e}", v);
    let exponent: i32 = sci.rsplit('e').next().unwrap().parse().unwrap();
    let decimals = (17 - exponent).max(0) as usize;
    let fixed = format!("{:.*}", decimals, v);
    if fixed.contains('.') {
        fixed
            .trim_end_matches('0')
            .trim_end_matches('.')
            .to_string()
    } else {
        fixed
    }
}

pub fn resolve(tool: &CompatTool) -> Result<String, String> {
    match tool {
        CompatTool::Name(name) => Ok(name.clone()),
        CompatTool::Path { path } => compat::tool_name(path),
    }
}

pub fn prepare(
    state: &State,
    steam_dir: &Path,
    record: &Record,
) -> Result<Option<Outcome>, String> {
    let path = steam_dir.join("config/config.vdf");
    let Some((original, mut tree)) = read_tree(&path)? else {
        log("config.vdf is missing, Steam has not finished its first start");
        return Ok(None);
    };
    let prev = record.keys_for(FILE);
    let mut managed = Managed::new(FILE, &prev);
    for (id, tool) in state.compat_tools() {
        let name = resolve(tool)?;
        let id = id.to_string();
        let priority = if id == "0" { "75" } else { "250" };
        let mut block = MAPPING.to_vec();
        block.push(&id);
        managed.set_block(
            &mut tree,
            &block,
            "name",
            &[("config", ""), ("name", &name), ("priority", priority)],
        );
    }
    if let Some(scale) = state.desktop_ui_scale {
        managed.set_leaf(&mut tree, &SCALE, &format_g18(scale as f32 as f64));
    }
    managed.revert(&mut tree);
    let delta = Delta::Keys(FILE.into(), managed.finish());
    Ok(Some(text_outcome(
        "config.vdf",
        &path,
        &original,
        &tree,
        delta,
    )))
}

#[cfg(test)]
mod tests {
    use super::{format_g18, prepare};
    use crate::record::Record;
    use crate::writers::testing::{state, temp, write};
    use crate::writers::{Delta, Outcome};
    use serde_json::json;
    use std::fs;
    use std::path::PathBuf;
    use steam_config_vdf::text::parse;

    const CONFIG: &str = "\"InstallConfigStore\"\n{\n\t\"Accessibility\"\n\t{\n\t}\n\t\"Software\"\n\t{\n\t\t\"Valve\"\n\t\t{\n\t\t\t\"Steam\"\n\t\t\t{\n\t\t\t\t\"CompatToolMapping\"\n\t\t\t\t{\n\t\t\t\t\t\"620\"\n\t\t\t\t\t{\n\t\t\t\t\t\t\"config\"\t\t\"\"\n\t\t\t\t\t\t\"name\"\t\t\"user_tool\"\n\t\t\t\t\t\t\"priority\"\t\t\"250\"\n\t\t\t\t\t}\n\t\t\t\t}\n\t\t\t}\n\t\t}\n\t}\n}\n";

    fn value(text: &str, path: &[&str]) -> Option<String> {
        parse(text)
            .unwrap()
            .find_path(path)
            .and_then(|n| n.value.clone())
    }

    fn mapping(id: &str, leaf: &str) -> Vec<&'static str> {
        let mut p = vec![
            "InstallConfigStore",
            "Software",
            "Valve",
            "Steam",
            "CompatToolMapping",
        ];
        p.push(Box::leak(id.to_string().into_boxed_str()));
        p.push(Box::leak(leaf.to_string().into_boxed_str()));
        p
    }

    fn run(steam: &PathBuf, extra: &str, record: &mut Record) -> Option<Outcome> {
        let outcome = prepare(&state(extra), steam, record).unwrap()?;
        if let Some(bytes) = &outcome.bytes {
            fs::write(&outcome.path, bytes).unwrap();
        }
        Some(outcome)
    }

    fn apply(steam: &PathBuf, extra: &str, record: &mut Record) {
        if let Some(outcome) = run(steam, extra, record) {
            record.apply(outcome.delta);
        }
    }

    #[test]
    fn formats_the_scale_like_steam() {
        assert_eq!(format_g18(1.25), "1.25");
        assert_eq!(format_g18(1.1f32 as f64), "1.10000002384185791");
        assert_eq!(format_g18(1.0), "1");
        assert_eq!(format_g18(0.5), "0.5");
        assert_eq!(format_g18(0.7f32 as f64), "0.699999988079071045");
        assert_eq!(format_g18(2.0), "2");
        assert_eq!(format_g18(1.15f32 as f64), "1.14999997615814209");
    }

    #[test]
    fn writes_mappings_with_priorities_and_records_priors() {
        let steam = temp("config-write");
        write(&steam.join("config/config.vdf"), CONFIG);
        let tool = steam.join("tool");
        write(
            &tool.join("compatibilitytool.vdf"),
            "\"compatibilitytools\"\n{\n\t\"compat_tools\"\n\t{\n\t\t\"scn_tool\"\n\t\t{\n\t\t}\n\t}\n}\n",
        );
        let extra = format!(
            r#""globalCompatTool": "GE-Proton", "desktopUiScale": 1.25, "apps": {{"620": {{"compatTool": {{"path": "{}"}}}}}}, "shortcuts": {{"4132570534": {{"name": "p", "exe": "/e", "dir": "/d", "compatTool": "proton_9"}}}}"#,
            tool.display()
        );
        let mut record = Record::default();
        let outcome = run(&steam, &extra, &mut record).unwrap();
        assert!(outcome.bytes.is_some());
        let text = fs::read_to_string(steam.join("config/config.vdf")).unwrap();
        assert_eq!(
            value(&text, &mapping("0", "name")).as_deref(),
            Some("GE-Proton")
        );
        assert_eq!(
            value(&text, &mapping("0", "priority")).as_deref(),
            Some("75")
        );
        assert_eq!(
            value(&text, &mapping("620", "name")).as_deref(),
            Some("scn_tool")
        );
        assert_eq!(
            value(&text, &mapping("620", "priority")).as_deref(),
            Some("250")
        );
        assert_eq!(
            value(&text, &mapping("4132570534", "name")).as_deref(),
            Some("proton_9")
        );
        assert_eq!(
            value(
                &text,
                &["InstallConfigStore", "Accessibility", "DesktopUIScale"]
            )
            .as_deref(),
            Some("1.25")
        );
        let Delta::Keys(file, entries) = outcome.delta else {
            panic!()
        };
        assert_eq!(file, "config");
        assert_eq!(entries.len(), 4);
        let e620 = entries
            .iter()
            .find(|e| e.path.last().unwrap() == "620")
            .unwrap();
        assert_eq!(
            e620.prior,
            json!({"config": "", "name": "user_tool", "priority": "250"})
        );
        assert_eq!(e620.ours, "scn_tool");
        let scale = entries
            .iter()
            .find(|e| e.path.last().unwrap() == "DesktopUIScale")
            .unwrap();
        assert_eq!(scale.prior, serde_json::Value::Null);
    }

    #[test]
    fn second_run_writes_nothing_and_removal_restores() {
        let steam = temp("config-restore");
        write(&steam.join("config/config.vdf"), CONFIG);
        let extra = r#""globalCompatTool": "GE-Proton", "desktopUiScale": 1.25, "apps": {"620": {"compatTool": "proton_9"}}"#;
        let mut record = Record::default();
        apply(&steam, extra, &mut record);
        assert_eq!(record.keys.len(), 3);
        let outcome = run(&steam, extra, &mut record).unwrap();
        assert!(outcome.bytes.is_none());
        apply(&steam, "", &mut record);
        assert!(record.keys.is_empty());
        assert_eq!(
            fs::read_to_string(steam.join("config/config.vdf")).unwrap(),
            CONFIG
        );
    }

    #[test]
    fn a_value_the_user_changed_is_kept_on_removal() {
        let steam = temp("config-user");
        write(&steam.join("config/config.vdf"), CONFIG);
        let mut record = Record::default();
        apply(
            &steam,
            r#""apps": {"620": {"compatTool": "proton_9"}}, "desktopUiScale": 1.25"#,
            &mut record,
        );
        let path = steam.join("config/config.vdf");
        let text = fs::read_to_string(&path)
            .unwrap()
            .replace("proton_9", "user-tool")
            .replace("1.25", "2");
        fs::write(&path, text).unwrap();
        apply(&steam, "", &mut record);
        let text = fs::read_to_string(&path).unwrap();
        assert_eq!(
            value(&text, &mapping("620", "name")).as_deref(),
            Some("user-tool")
        );
        assert_eq!(
            value(
                &text,
                &["InstallConfigStore", "Accessibility", "DesktopUIScale"]
            )
            .as_deref(),
            Some("2")
        );
        assert!(record.keys.is_empty());
    }

    #[test]
    fn missing_file_is_skipped_and_a_bad_tool_is_an_error() {
        let steam = temp("config-missing");
        let record = Record::default();
        assert!(prepare(&state(""), &steam, &record).unwrap().is_none());
        write(&steam.join("config/config.vdf"), CONFIG);
        let extra = format!(
            r#""globalCompatTool": {{"path": "{}"}}"#,
            steam.join("no-tool").display()
        );
        assert!(prepare(&state(&extra), &steam, &record).is_err());
        write(&steam.join("config/config.vdf"), "\"broken");
        assert!(prepare(&state(""), &steam, &record).is_err());
    }
}
