use std::path::Path;
use std::process::{Command, Stdio};

use crate::launch::env::EnvPlan;

pub fn log(msg: impl AsRef<str>) {
    eprintln!("steam-config-nix: {}", msg.as_ref());
}

pub fn notify(bin: Option<&Path>, body: &str) {
    notify_in(bin, body, None);
}

pub fn notify_in(bin: Option<&Path>, body: &str, plan: Option<&EnvPlan>) {
    let Some(bin) = bin else { return };
    let mut cmd = Command::new(bin);
    if let Some(plan) = plan {
        plan.apply(&mut cmd);
    }
    let _ = cmd
        .args(["-a", "steam-config-nix", "steam-config-nix", body])
        .env_remove("LD_LIBRARY_PATH")
        .env_remove("LD_PRELOAD")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}
