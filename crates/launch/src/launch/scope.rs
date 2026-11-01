use std::ffi::OsString;
use std::process::{Command, Stdio};

use super::env::EnvPlan;
use super::spec::Scope;

pub const STEAM_SCOPE: &str = "STEAM_LAUNCH_WRAPPER_SCOPE";

pub fn steam_off(plan: &mut EnvPlan) {
    plan.set(STEAM_SCOPE, "0", "systemd");
}

pub fn unit(app_id: u64, pid: impl std::fmt::Display) -> String {
    format!("app-steam-{app_id}-{pid}.scope")
}

pub fn head(scope: &Scope, unit: &str) -> Vec<OsString> {
    let mut argv: Vec<OsString> = vec![
        scope.systemd_run.clone().into(),
        "--user".into(),
        "--scope".into(),
        "--quiet".into(),
        "--collect".into(),
        "--expand-environment=no".into(),
        format!("--unit={unit}").into(),
    ];
    argv.extend(
        scope
            .properties
            .iter()
            .map(|(k, v)| OsString::from(format!("--property={k}={v}"))),
    );
    argv.push("--".into());
    argv
}

pub fn probe(scope: &Scope, plan: &EnvPlan) -> bool {
    let mut cmd = Command::new(&scope.systemctl);
    cmd.args(["--user", "show", "--property=Version"])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    plan.apply(&mut cmd).status().is_ok_and(|s| s.success())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn head_argv() {
        let scope = Scope {
            systemd_run: "/s/systemd-run".into(),
            systemctl: "/s/systemctl".into(),
            properties: [("Slice", "games.slice"), ("CPUWeight", "150")]
                .iter()
                .map(|(k, v)| (k.to_string(), v.to_string()))
                .collect(),
        };
        assert_eq!(
            head(&scope, &unit(620, 42)),
            [
                "/s/systemd-run",
                "--user",
                "--scope",
                "--quiet",
                "--collect",
                "--expand-environment=no",
                "--unit=app-steam-620-42.scope",
                "--property=CPUWeight=150",
                "--property=Slice=games.slice",
                "--"
            ]
        );
    }
}
