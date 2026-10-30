use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

use serde::Deserialize;

#[derive(Debug, Clone, Copy, PartialEq, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum OnSteamRunning {
    Wait,
    Close,
    ForceClose,
    Skip,
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(untagged)]
pub enum CompatTool {
    Name(String),
    Path { path: PathBuf },
}

#[derive(Debug, Clone, Default, PartialEq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Artwork {
    #[serde(default)]
    pub cover: Option<String>,
    #[serde(default)]
    pub header: Option<String>,
    #[serde(default)]
    pub hero: Option<String>,
    #[serde(default)]
    pub logo: Option<String>,
}

impl Artwork {
    pub fn slots(&self) -> [(&'static str, Option<&str>); 4] {
        [
            ("p", self.cover.as_deref()),
            ("", self.header.as_deref()),
            ("_hero", self.hero.as_deref()),
            ("_logo", self.logo.as_deref()),
        ]
    }
}

#[derive(Debug, Clone, Default, PartialEq, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct App {
    #[serde(default)]
    pub compat_tool: Option<CompatTool>,
    #[serde(default)]
    pub beta: Option<String>,
    #[serde(default)]
    pub language: Option<String>,
    #[serde(default)]
    pub overlay: Option<bool>,
    #[serde(default)]
    pub steam_input: Option<u8>,
    #[serde(default)]
    pub update_behavior: Option<u8>,
    #[serde(default)]
    pub background_downloads: Option<u8>,
    #[serde(default)]
    pub library_icon: bool,
    #[serde(default)]
    pub artwork: Artwork,
}

impl App {
    pub fn manifest_settings(&self) -> Vec<(Vec<&'static str>, String)> {
        let mut settings = Vec::new();
        if let Some(beta) = &self.beta {
            settings.push((vec!["AppState", "UserConfig", "BetaKey"], beta.clone()));
        }
        if let Some(language) = &self.language {
            settings.push((vec!["AppState", "UserConfig", "language"], language.clone()));
        }
        if let Some(v) = self.update_behavior {
            settings.push((vec!["AppState", "AutoUpdateBehavior"], v.to_string()));
        }
        if let Some(v) = self.background_downloads {
            settings.push((
                vec!["AppState", "AllowOtherDownloadsWhileRunning"],
                v.to_string(),
            ));
        }
        settings
    }
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Shortcut {
    pub name: String,
    pub exe: String,
    #[serde(default)]
    pub dir: String,
    #[serde(default)]
    pub icon: Option<String>,
    #[serde(default)]
    pub vr: Option<bool>,
    #[serde(default)]
    pub overlay: Option<bool>,
    #[serde(default)]
    pub hidden: Option<bool>,
    #[serde(default)]
    pub compat_tool: Option<CompatTool>,
    #[serde(default)]
    pub artwork: Artwork,
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct State {
    pub on_steam_running: OnSteamRunning,
    pub steam: PathBuf,
    #[serde(default)]
    pub notify_send: Option<PathBuf>,
    #[serde(default)]
    pub library_folders: Vec<String>,
    #[serde(default)]
    pub global_compat_tool: Option<CompatTool>,
    #[serde(default)]
    pub display_rates_as_bits: Option<bool>,
    #[serde(default)]
    pub desktop_ui_scale: Option<f64>,
    #[serde(default)]
    pub apps: BTreeMap<u32, App>,
    #[serde(default)]
    pub shortcuts: BTreeMap<u32, Shortcut>,
}

impl State {
    pub fn load(path: &Path) -> Result<State, String> {
        let text = fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))?;
        State::parse(&text).map_err(|e| format!("{}: {e}", path.display()))
    }

    pub fn parse(text: &str) -> Result<State, String> {
        serde_json::from_str(text).map_err(|e| e.to_string())
    }

    pub fn compat_tools(&self) -> Vec<(u32, &CompatTool)> {
        let mut tools = Vec::new();
        if let Some(tool) = &self.global_compat_tool {
            tools.push((0, tool));
        }
        for (id, app) in &self.apps {
            if let Some(tool) = &app.compat_tool {
                tools.push((*id, tool));
            }
        }
        for (id, shortcut) in &self.shortcuts {
            if let Some(tool) = &shortcut.compat_tool {
                tools.push((*id, tool));
            }
        }
        tools
    }

    pub fn artwork(&self) -> Vec<(u32, &Artwork)> {
        self.apps
            .iter()
            .map(|(id, app)| (*id, &app.artwork))
            .chain(self.shortcuts.iter().map(|(id, s)| (*id, &s.artwork)))
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::{CompatTool, OnSteamRunning, State};

    const FULL: &str = r#"{
        "onSteamRunning": "force-close",
        "steam": "/nix/store/x-steam/bin/steam",
        "notifySend": "/nix/store/y/bin/notify-send",
        "libraryFolders": ["/mnt/games"],
        "globalCompatTool": "GE-Proton",
        "displayRatesAsBits": true,
        "desktopUiScale": 1.25,
        "apps": {
            "620": {"compatTool": {"path": "/nix/store/z-tool"}, "beta": "prerelease", "language": "german",
                    "overlay": false, "steamInput": 2, "updateBehavior": 1, "backgroundDownloads": 2,
                    "libraryIcon": true, "artwork": {"cover": "/nix/store/c.png"}},
            "105600": {}
        },
        "shortcuts": {
            "4132570534": {"name": "probe", "exe": "/opt/probe/run", "dir": "/opt/probe", "vr": true,
                           "overlay": false, "hidden": true, "icon": "/nix/store/i.png",
                           "compatTool": "proton_9", "artwork": {"hero": "/nix/store/h.jpg"}}
        }
    }"#;

    #[test]
    fn parses_the_full_shape() {
        let state = State::parse(FULL).unwrap();
        assert_eq!(state.on_steam_running, OnSteamRunning::ForceClose);
        assert_eq!(state.library_folders, vec!["/mnt/games"]);
        assert_eq!(
            state.global_compat_tool,
            Some(CompatTool::Name("GE-Proton".into()))
        );
        assert_eq!(state.desktop_ui_scale, Some(1.25));
        let app = &state.apps[&620];
        assert_eq!(
            app.compat_tool,
            Some(CompatTool::Path {
                path: "/nix/store/z-tool".into()
            })
        );
        assert_eq!(app.steam_input, Some(2));
        assert!(app.library_icon);
        assert!(!state.apps[&105600].library_icon);
        let shortcut = &state.shortcuts[&4132570534];
        assert_eq!(shortcut.hidden, Some(true));
        assert_eq!(shortcut.artwork.hero.as_deref(), Some("/nix/store/h.jpg"));
        let ids: Vec<u32> = state.compat_tools().iter().map(|(id, _)| *id).collect();
        assert_eq!(ids, vec![0, 620, 4132570534]);
        assert_eq!(state.artwork().len(), 3);
    }

    #[test]
    fn minimal_state_fills_defaults() {
        let state = State::parse(r#"{"onSteamRunning": "wait", "steam": "/bin/steam"}"#).unwrap();
        assert_eq!(state.on_steam_running, OnSteamRunning::Wait);
        assert!(state.notify_send.is_none());
        assert!(state.apps.is_empty());
        assert!(state.shortcuts.is_empty());
        assert!(state.compat_tools().is_empty());
    }

    #[test]
    fn manifest_settings_follow_the_set_fields() {
        let state = State::parse(FULL).unwrap();
        let settings = state.apps[&620].manifest_settings();
        let keys: Vec<&str> = settings.iter().map(|(p, _)| *p.last().unwrap()).collect();
        assert_eq!(
            keys,
            vec![
                "BetaKey",
                "language",
                "AutoUpdateBehavior",
                "AllowOtherDownloadsWhileRunning"
            ]
        );
        assert_eq!(settings[2].1, "1");
        assert!(state.apps[&105600].manifest_settings().is_empty());
    }

    #[test]
    fn a_shortcut_without_dir_gets_an_empty_one() {
        let state = State::parse(
            r#"{"onSteamRunning": "wait", "steam": "/s", "shortcuts": {"5": {"name": "g", "exe": "/e"}}}"#,
        )
        .unwrap();
        assert_eq!(state.shortcuts[&5].dir, "");
    }

    #[test]
    fn unknown_fields_and_values_are_rejected() {
        assert!(State::parse(r#"{"onSteamRunning": "wait", "steam": "/s", "extra": 1}"#).is_err());
        assert!(
            State::parse(r#"{"onSteamRunning": "wait", "steam": "/s", "apps": {"1": {"x": 1}}}"#)
                .is_err()
        );
        assert!(State::parse(r#"{"onSteamRunning": "sometimes", "steam": "/s"}"#).is_err());
        assert!(State::parse(r#"{"steam": "/s"}"#).is_err());
    }
}
