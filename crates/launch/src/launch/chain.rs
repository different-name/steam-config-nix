use std::ffi::OsString;
use std::path::Path;

pub struct Links<'a> {
    pub scope_head: Option<Vec<OsString>>,
    pub self_exe: &'a Path,
    pub files: Option<&'a Path>,
    pub env_program: Option<&'a Path>,
    pub wrappers: &'a [String],
    pub cmdline: &'a str,
}

pub fn links(input: Links) -> Vec<Vec<OsString>> {
    let mut links = Vec::new();
    if let Some(head) = input.scope_head {
        links.push(head);
    }
    if let Some(files) = input.files {
        links.push(vec![
            input.self_exe.into(),
            "launch".into(),
            files.into(),
            "--".into(),
        ]);
    }
    if !input.wrappers.is_empty() {
        let mut link: Vec<OsString> = vec![
            input.env_program.unwrap_or(Path::new("env")).into(),
            "--".into(),
        ];
        link.extend(input.wrappers.iter().map(OsString::from));
        links.push(link);
    }
    links.push(vec!["/bin/sh".into(), "-c".into(), input.cmdline.into()]);
    links
}

pub fn argv(links: Vec<Vec<OsString>>) -> Vec<OsString> {
    links.into_iter().flatten().collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::launch::scope;
    use crate::launch::spec::{Scope, strip_deleted};

    fn base<'a>(wrappers: &'a [String]) -> Links<'a> {
        Links {
            scope_head: None,
            self_exe: Path::new("/d/launch-shell"),
            files: None,
            env_program: None,
            wrappers,
            cmdline: "game",
        }
    }

    fn strings(v: Vec<OsString>) -> Vec<String> {
        v.into_iter().map(|s| s.into_string().unwrap()).collect()
    }

    #[test]
    fn files_only() {
        let chain = links(Links {
            files: Some(Path::new("/s/files.json")),
            ..base(&[])
        });
        assert_eq!(
            strings(argv(chain)),
            [
                "/d/launch-shell",
                "launch",
                "/s/files.json",
                "--",
                "/bin/sh",
                "-c",
                "game"
            ]
        );
    }

    #[test]
    fn nothing_but_sh() {
        assert_eq!(strings(argv(links(base(&[])))), ["/bin/sh", "-c", "game"]);
    }

    #[test]
    fn scope_only() {
        let s = Scope {
            systemd_run: "/s/run".into(),
            systemctl: "/s/ctl".into(),
            properties: Default::default(),
        };
        let chain = links(Links {
            scope_head: Some(scope::head(&s, "u.scope")),
            ..base(&[])
        });
        let argv = strings(argv(chain));
        assert!(argv.contains(&"--collect".to_string()));
        assert_eq!(&argv[argv.len() - 4..], ["--", "/bin/sh", "-c", "game"]);
    }

    #[test]
    fn everything_in_order() {
        let wrappers: Vec<String> = ["A=1", "-x", "/g/gamescope", "--"]
            .iter()
            .map(|s| s.to_string())
            .collect();
        let chain = links(Links {
            scope_head: Some(vec!["run".into(), "--".into()]),
            files: Some(Path::new("/s/files.json")),
            env_program: Some(Path::new("/c/env")),
            ..base(&wrappers)
        });
        assert_eq!(chain.len(), 4);
        assert_eq!(
            strings(argv(chain)),
            [
                "run",
                "--",
                "/d/launch-shell",
                "launch",
                "/s/files.json",
                "--",
                "/c/env",
                "--",
                "A=1",
                "-x",
                "/g/gamescope",
                "--",
                "/bin/sh",
                "-c",
                "game"
            ]
        );
    }

    #[test]
    fn deleted_self() {
        let exe = strip_deleted("/d/launch-shell (deleted)".into());
        let chain = links(Links {
            self_exe: &exe,
            files: Some(Path::new("/f")),
            ..base(&[])
        });
        assert_eq!(chain[0][0], OsString::from("/d/launch-shell"));
    }
}
