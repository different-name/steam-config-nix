use std::collections::BTreeMap;
use std::ffi::{OsStr, OsString};
use std::os::unix::ffi::OsStrExt;
use std::process::Command;

use crate::notify::log;

pub struct Entry {
    pub name: OsString,
    pub value: Option<OsString>,
    pub source: &'static str,
}

#[derive(Default)]
pub struct EnvPlan {
    base: Option<Vec<(OsString, OsString)>>,
    pub entries: Vec<Entry>,
}

pub fn valid_name(name: &OsStr) -> bool {
    let bytes = name.as_bytes();
    !bytes.is_empty() && !bytes.contains(&b'=') && !bytes.contains(&0)
}

impl EnvPlan {
    pub fn with_base(base: Vec<(OsString, OsString)>) -> Self {
        EnvPlan {
            base: Some(base),
            entries: Vec::new(),
        }
    }

    pub fn push(
        &mut self,
        name: impl Into<OsString>,
        value: Option<OsString>,
        source: &'static str,
    ) {
        let name = name.into();
        if !valid_name(&name) {
            log(format!(
                "{source}: {:?} is not a valid variable name, skipped",
                name.to_string_lossy()
            ));
            return;
        }
        if value.as_ref().is_some_and(|v| v.as_bytes().contains(&0)) {
            log(format!(
                "{source}: {} contains NUL, skipped",
                name.to_string_lossy()
            ));
            return;
        }
        self.entries.push(Entry {
            name,
            value,
            source,
        });
    }

    pub fn set(&mut self, name: &str, value: impl Into<OsString>, source: &'static str) {
        self.push(name, Some(value.into()), source);
    }

    pub fn extend(&mut self, env: &BTreeMap<String, Option<String>>, source: &'static str) {
        for (name, value) in env {
            self.push(name, value.as_ref().map(OsString::from), source);
        }
    }

    pub fn get(&self, name: &str) -> Option<OsString> {
        if let Some(entry) = self.entries.iter().rev().find(|e| e.name == name) {
            return entry.value.clone();
        }
        match &self.base {
            Some(base) => base
                .iter()
                .rev()
                .find(|(n, _)| n == name)
                .map(|(_, v)| v.clone()),
            None => std::env::var_os(name),
        }
    }

    pub fn apply<'a>(&self, cmd: &'a mut Command) -> &'a mut Command {
        if let Some(base) = &self.base {
            cmd.env_clear();
            cmd.envs(base.iter().map(|(n, v)| (n, v)));
        }
        for entry in &self.entries {
            match &entry.value {
                Some(v) => cmd.env(&entry.name, v),
                None => cmd.env_remove(&entry.name),
            };
        }
        cmd
    }
}

pub fn dll_overrides(dlls: &BTreeMap<String, String>) -> Option<String> {
    if dlls.is_empty() {
        return None;
    }
    let parts: Vec<String> = dlls
        .iter()
        .map(|(dll, mode)| {
            let mode = if mode == "disabled" { "" } else { mode };
            format!("{dll}={mode}")
        })
        .collect();
    Some(parts.join(";"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn map(pairs: &[(&str, Option<&str>)]) -> BTreeMap<String, Option<String>> {
        pairs
            .iter()
            .map(|(k, v)| (k.to_string(), v.map(str::to_string)))
            .collect()
    }

    #[test]
    fn dll_string() {
        let dlls = [("winhttp", "n,b"), ("d3d9", "disabled")]
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect();
        assert_eq!(dll_overrides(&dlls).as_deref(), Some("d3d9=;winhttp=n,b"));
        assert_eq!(dll_overrides(&BTreeMap::new()), None);
    }

    #[test]
    fn invalid_names_skipped() {
        let mut plan = EnvPlan::with_base(Vec::new());
        plan.extend(
            &map(&[
                ("", Some("x")),
                ("A=B", Some("x")),
                ("A\0", Some("x")),
                ("ok-name", Some("1")),
            ]),
            "env",
        );
        let names: Vec<_> = plan.entries.iter().map(|e| e.name.clone()).collect();
        assert_eq!(names, vec![OsString::from("ok-name")]);
    }

    #[test]
    fn get_walks_back_to_base() {
        let mut plan = EnvPlan::with_base(vec![("STEAM_COMPAT_DATA_PATH".into(), "/steam".into())]);
        assert_eq!(plan.get("STEAM_COMPAT_DATA_PATH"), Some("/steam".into()));
        plan.extend(&map(&[("STEAM_COMPAT_DATA_PATH", Some("/env"))]), "env");
        assert_eq!(plan.get("STEAM_COMPAT_DATA_PATH"), Some("/env".into()));
        plan.extend(&map(&[("STEAM_COMPAT_DATA_PATH", None)]), "env");
        assert_eq!(plan.get("STEAM_COMPAT_DATA_PATH"), None);
        assert_eq!(plan.get("MISSING"), None);
    }

    #[test]
    fn apply_reaches_child() {
        let mut plan = EnvPlan::with_base(vec![
            ("KEEP".into(), "k".into()),
            ("DROP".into(), "d".into()),
        ]);
        plan.set("NEW", "n", "env");
        plan.push("DROP", None, "env");
        let mut cmd = Command::new("/bin/sh");
        cmd.args([
            "-c",
            "printf '%s|%s|%s' \"$KEEP\" \"${DROP-unset}\" \"$NEW\"",
        ]);
        let out = plan.apply(&mut cmd).output().unwrap();
        assert_eq!(String::from_utf8_lossy(&out.stdout), "k|unset|n");
    }
}
