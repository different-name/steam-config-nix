use std::ffi::{OsStr, OsString};
use std::path::{Path, PathBuf};

use super::spec::Winetricks;

pub const MARKER: &str = "steam-config-nix-winetricks";

#[derive(Debug, PartialEq)]
pub enum Decision {
    Skip,
    SkipLogged(String),
    Installed,
    Run {
        want: String,
        marker: PathBuf,
        previous: Option<String>,
        argv: Vec<OsString>,
    },
}

pub struct Inputs<'a> {
    pub compat: Option<&'a OsStr>,
    pub orig: Option<&'a OsStr>,
    pub prefix_path: bool,
    pub app_id: Option<&'a OsStr>,
}

pub fn want(w: &Winetricks) -> String {
    w.verbs.join(" ")
}

pub fn read_marker(path: &Path) -> Option<String> {
    let text = std::fs::read_to_string(path).ok()?;
    Some(text.trim_end_matches('\n').to_string())
}

pub fn decide(w: &Winetricks, input: &Inputs) -> Decision {
    let Some(compat) = input.compat.filter(|c| !c.is_empty()).map(Path::new) else {
        return Decision::Skip;
    };
    if !compat.join("pfx").is_dir() {
        return Decision::Skip;
    }
    let orig = if input.prefix_path {
        let Some(orig) = input.orig.filter(|o| !o.is_empty()) else {
            return Decision::Skip;
        };
        if !Path::new(orig).is_dir() {
            return Decision::SkipLogged(format!(
                "winetricks skipped, {} does not exist",
                orig.to_string_lossy()
            ));
        }
        Some(orig)
    } else {
        None
    };
    let Some(app_id) = input.app_id.filter(|a| !a.is_empty()) else {
        return Decision::SkipLogged(
            "winetricks skipped, STEAM_COMPAT_APP_ID is not set".to_string(),
        );
    };
    let want = want(w);
    let marker = compat.join(MARKER);
    let previous = read_marker(&marker);
    if previous.as_deref() == Some(want.as_str()) {
        return Decision::Installed;
    }
    Decision::Run {
        want,
        marker,
        previous,
        argv: argv(w, compat.as_os_str(), orig, app_id),
    }
}

pub fn argv(w: &Winetricks, compat: &OsStr, orig: Option<&OsStr>, app_id: &OsStr) -> Vec<OsString> {
    let mut argv: Vec<OsString> = Vec::new();
    if let (Some(bwrap), Some(orig)) = (&w.bwrap, orig) {
        argv.extend([
            bwrap.into(),
            "--dev-bind".into(),
            "/".into(),
            "/".into(),
            "--bind".into(),
            compat.into(),
            orig.into(),
            "--".into(),
        ]);
    }
    argv.push(w.protontricks.clone().into());
    argv.push(app_id.into());
    argv.push("-q".into());
    argv.extend(w.verbs.iter().map(OsString::from));
    argv
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::launch::spec::tests::temp;
    use std::fs;

    fn tricks(bwrap: bool) -> Winetricks {
        Winetricks {
            verbs: vec!["corefonts".into(), "vcrun2022".into()],
            protontricks: "/p/protontricks".into(),
            bwrap: bwrap.then(|| "/b/bwrap".into()),
        }
    }

    fn inputs<'a>(compat: &'a Path, orig: Option<&'a Path>) -> Inputs<'a> {
        Inputs {
            compat: Some(compat.as_os_str()),
            orig: orig.map(Path::as_os_str),
            prefix_path: orig.is_some(),
            app_id: Some(OsStr::new("620")),
        }
    }

    #[test]
    fn marker_states() {
        let root = temp("winetricks-marker");
        fs::create_dir_all(root.join("pfx")).unwrap();
        let w = tricks(false);
        let marker = root.join(MARKER);

        fs::write(&marker, "corefonts vcrun2022").unwrap();
        assert_eq!(decide(&w, &inputs(&root, None)), Decision::Installed);
        fs::write(&marker, "corefonts vcrun2022\n").unwrap();
        assert_eq!(decide(&w, &inputs(&root, None)), Decision::Installed);

        fs::write(&marker, "vcrun2022 corefonts").unwrap();
        assert!(matches!(
            decide(&w, &inputs(&root, None)),
            Decision::Run { previous: Some(p), .. } if p == "vcrun2022 corefonts"
        ));
        fs::remove_file(&marker).unwrap();
        assert!(matches!(
            decide(&w, &inputs(&root, None)),
            Decision::Run { previous: None, .. }
        ));
        fs::create_dir(&marker).unwrap();
        assert!(matches!(
            decide(&w, &inputs(&root, None)),
            Decision::Run { previous: None, .. }
        ));
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn skip_rules() {
        let root = temp("winetricks-skip");
        let w = tricks(true);
        let none = Inputs {
            compat: None,
            orig: None,
            prefix_path: false,
            app_id: Some(OsStr::new("620")),
        };
        assert_eq!(decide(&w, &none), Decision::Skip);
        assert_eq!(decide(&w, &inputs(&root, None)), Decision::Skip);

        fs::create_dir_all(root.join("pfx")).unwrap();
        let empty_orig = Inputs {
            orig: Some(OsStr::new("")),
            prefix_path: true,
            ..inputs(&root, None)
        };
        assert_eq!(decide(&w, &empty_orig), Decision::Skip);
        let missing = root.join("missing");
        assert!(matches!(
            decide(&w, &inputs(&root, Some(&missing))),
            Decision::SkipLogged(m) if m.contains("does not exist")
        ));
        let no_app = Inputs {
            app_id: None,
            ..inputs(&root, None)
        };
        assert!(
            matches!(decide(&w, &no_app), Decision::SkipLogged(m) if m.contains("STEAM_COMPAT_APP_ID"))
        );
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn argv_shapes() {
        let plain = argv(&tricks(false), OsStr::new("/c"), None, OsStr::new("620"));
        assert_eq!(
            plain,
            ["/p/protontricks", "620", "-q", "corefonts", "vcrun2022"]
        );
        let bound = argv(
            &tricks(true),
            OsStr::new("/c"),
            Some(OsStr::new("/o")),
            OsStr::new("620"),
        );
        assert_eq!(
            bound,
            [
                "/b/bwrap",
                "--dev-bind",
                "/",
                "/",
                "--bind",
                "/c",
                "/o",
                "--",
                "/p/protontricks",
                "620",
                "-q",
                "corefonts",
                "vcrun2022"
            ]
        );
    }
}
