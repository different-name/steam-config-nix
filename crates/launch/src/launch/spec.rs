use std::collections::BTreeMap;
use std::ffi::OsString;
use std::path::{Path, PathBuf};

use serde::Deserialize;

#[derive(Deserialize, Debug, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum Kind {
    Steam,
    NonSteam,
}

#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct LaunchSpec {
    pub version: u32,
    pub key: String,
    pub app_id: u64,
    pub kind: Kind,
    pub name: String,
    pub notify_send: Option<PathBuf>,
    pub env: BTreeMap<String, Option<String>>,
    pub dll_overrides: BTreeMap<String, String>,
    pub prefix_path: Option<PathBuf>,
    pub winetricks: Option<Winetricks>,
    pub pre_hook: Option<String>,
    pub shell: Option<PathBuf>,
    pub raw_launch_options: Option<String>,
    pub args: Vec<String>,
    pub wrappers: Vec<String>,
    pub env_program: Option<PathBuf>,
    pub scope: Option<Scope>,
    pub steam_scope: Option<bool>,
    pub files: Option<PathBuf>,
}

#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Winetricks {
    pub verbs: Vec<String>,
    pub protontricks: PathBuf,
    pub bwrap: Option<PathBuf>,
}

#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Scope {
    pub systemd_run: PathBuf,
    pub systemctl: PathBuf,
    pub properties: BTreeMap<String, String>,
}

#[derive(Deserialize, Debug, Default)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct GlobalSpec {
    pub version: u32,
    pub notify_send: Option<PathBuf>,
    pub env: BTreeMap<String, Option<String>>,
}

trait Versioned {
    fn version(&self) -> u32;
}

impl Versioned for LaunchSpec {
    fn version(&self) -> u32 {
        self.version
    }
}

impl Versioned for GlobalSpec {
    fn version(&self) -> u32 {
        self.version
    }
}

fn parse<T: for<'de> Deserialize<'de> + Versioned>(text: &str) -> Result<T, String> {
    let spec: T = serde_json::from_str(text).map_err(|e| e.to_string())?;
    match spec.version() {
        1 => Ok(spec),
        v => Err(format!("unsupported version {v}")),
    }
}

pub fn parse_app(text: &str) -> Result<LaunchSpec, String> {
    parse(text)
}

pub fn parse_global(text: &str) -> Result<GlobalSpec, String> {
    parse(text)
}

pub fn read(path: &Path) -> Result<Option<String>, String> {
    match std::fs::read_to_string(path) {
        Ok(text) => Ok(Some(text)),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(format!("{}: {e}", path.display())),
    }
}

pub fn load_app(path: &Path) -> Result<Option<LaunchSpec>, String> {
    match read(path)? {
        None => Ok(None),
        Some(text) => parse_app(&text)
            .map(Some)
            .map_err(|e| format!("{}: {e}", path.display())),
    }
}

pub fn load_global(path: &Path) -> Result<Option<GlobalSpec>, String> {
    match read(path)? {
        None => Ok(None),
        Some(text) => parse_global(&text)
            .map(Some)
            .map_err(|e| format!("{}: {e}", path.display())),
    }
}

pub fn strip_deleted(exe: PathBuf) -> PathBuf {
    match exe.to_str().and_then(|s| s.strip_suffix(" (deleted)")) {
        Some(s) => PathBuf::from(s),
        None => exe,
    }
}

pub fn user_data_base(xdg_data_home: Option<OsString>, home: Option<OsString>) -> Option<PathBuf> {
    let absolute = |v: OsString| Some(PathBuf::from(v)).filter(|p| p.is_absolute());
    xdg_data_home
        .and_then(absolute)
        .or_else(|| home.and_then(absolute).map(|h| h.join(".local/share")))
}

pub fn data_dir(xdg_data_home: Option<OsString>, home: Option<OsString>) -> PathBuf {
    let user = user_data_base(xdg_data_home, home).map(|base| base.join("steam-config-nix"));
    match user {
        Some(user) if user.join("state.json").exists() => user,
        _ => PathBuf::from("/var/lib/steam-config-nix"),
    }
}

pub fn current_data_dir() -> PathBuf {
    data_dir(std::env::var_os("XDG_DATA_HOME"), std::env::var_os("HOME"))
}

#[cfg(test)]
pub mod tests {
    use super::*;
    use std::fs;

    pub const PORTAL: &str = r#"{
  "version": 1,
  "key": "620",
  "appId": 620,
  "kind": "steam",
  "name": "Portal 2 (portal)",
  "notifySend": "/nix/store/x-libnotify/bin/notify-send",
  "env": { "DXVK_HUD": "fps", "PROTON_LOG": "1", "TZ": null },
  "dllOverrides": { "d3d9": "disabled", "winhttp": "n,b" },
  "prefixPath": "/mnt/games/prefixes/620",
  "winetricks": {
    "verbs": ["corefonts", "vcrun2022"],
    "protontricks": "/nix/store/x-protontricks/bin/protontricks",
    "bwrap": "/nix/store/x-bubblewrap/bin/bwrap"
  },
  "preHook": "export START=$(date +%s)\n",
  "shell": "/nix/store/x-bash/bin/bash",
  "rawLaunchOptions": "X=1 %command% -r",
  "args": ["-a", "two words"],
  "wrappers": ["/nix/store/x-gamescope/bin/gamescope", "-f", "--"],
  "envProgram": "/nix/store/x-coreutils/bin/env",
  "scope": {
    "systemdRun": "/nix/store/x-systemd/bin/systemd-run",
    "systemctl": "/nix/store/x-systemd/bin/systemctl",
    "properties": {
      "After": "steam-app-portal-2.target",
      "CPUWeight": "150",
      "Description": "Portal 2 (portal)",
      "Slice": "games.slice",
      "Wants": "steam-app-portal-2.target"
    }
  },
  "files": "/nix/store/x-steam-config-nix-files-620.json"
}"#;

    pub const PROBE: &str = r#"{
  "version": 1,
  "key": "probe",
  "appId": 4132570534,
  "kind": "nonSteam",
  "name": "probe",
  "notifySend": null,
  "env": { "SCN_APP": "probe" },
  "dllOverrides": {},
  "prefixPath": null,
  "winetricks": null,
  "preHook": null,
  "shell": null,
  "rawLaunchOptions": null,
  "args": ["--verbose"],
  "wrappers": [],
  "envProgram": null,
  "scope": null,
  "files": null
}"#;

    pub fn temp(name: &str) -> PathBuf {
        let dir =
            std::env::temp_dir().join(format!("scn-launch-test-{}-{name}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn fixtures_parse() {
        let portal = parse_app(PORTAL).unwrap();
        assert_eq!(portal.kind, Kind::Steam);
        assert_eq!(portal.env["TZ"], None);
        assert_eq!(portal.steam_scope, None);
        assert_eq!(portal.scope.unwrap().properties.len(), 5);
        let probe = parse_app(PROBE).unwrap();
        assert_eq!(probe.kind, Kind::NonSteam);
        assert_eq!(probe.app_id, 4132570534);
        let global =
            parse_global(r#"{ "version": 1, "notifySend": null, "env": { "A": "1" } }"#).unwrap();
        assert_eq!(global.env["A"].as_deref(), Some("1"));
    }

    #[test]
    fn steam_scope_parses() {
        let text = PROBE.replace("\"files\": null", "\"files\": null, \"steamScope\": false");
        assert_eq!(parse_app(&text).unwrap().steam_scope, Some(false));
    }

    #[test]
    fn unknown_field_fails() {
        let text = PROBE.replace("\"files\": null", "\"files\": null, \"extra\": 1");
        assert!(parse_app(&text).is_err());
    }

    #[test]
    fn other_version_fails() {
        let text = PROBE.replace("\"version\": 1", "\"version\": 2");
        assert!(parse_app(&text).unwrap_err().contains("version 2"));
    }

    #[test]
    fn number_in_env_fails() {
        let text = PROBE.replace("\"probe\" }", "1 }");
        assert!(parse_app(&text).is_err());
    }

    #[test]
    fn deleted_suffix_stripped() {
        assert_eq!(
            strip_deleted(PathBuf::from("/d/launch-shell (deleted)")),
            PathBuf::from("/d/launch-shell")
        );
        assert_eq!(
            strip_deleted(PathBuf::from("/d/launch-shell")),
            PathBuf::from("/d/launch-shell")
        );
    }

    #[test]
    fn data_dir_choice() {
        let root = temp("datadir");
        let xdg = root.join("xdg");
        let user = xdg.join("steam-config-nix");
        fs::create_dir_all(&user).unwrap();
        assert_eq!(
            data_dir(Some(xdg.clone().into()), None),
            PathBuf::from("/var/lib/steam-config-nix")
        );

        fs::write(user.join("state.json"), "{}").unwrap();
        assert_eq!(data_dir(Some(xdg.clone().into()), None), user);

        let home = root.join("home");
        fs::create_dir_all(home.join(".local/share/steam-config-nix")).unwrap();
        fs::write(home.join(".local/share/steam-config-nix/state.json"), "{}").unwrap();
        assert_eq!(
            data_dir(Some("".into()), Some(home.clone().into())),
            home.join(".local/share/steam-config-nix")
        );

        assert_eq!(
            data_dir(Some(root.join("none").into()), None),
            PathBuf::from("/var/lib/steam-config-nix")
        );
        assert_eq!(user_data_base(Some("".into()), Some("".into())), None);
        assert_eq!(user_data_base(None, None), None);
        assert_eq!(
            user_data_base(Some("rel".into()), Some("home".into())),
            None
        );
        assert_eq!(
            user_data_base(Some("rel".into()), Some("/h".into())),
            Some(PathBuf::from("/h/.local/share"))
        );
        let _ = fs::remove_dir_all(&root);
    }
}
