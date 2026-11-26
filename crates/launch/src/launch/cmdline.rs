pub fn splice(cmdline: &str, raw: Option<&str>) -> String {
    match raw {
        None | Some("") => cmdline.to_string(),
        Some(raw) if raw.contains("%command%") => raw.replace("%command%", cmdline),
        Some(raw) => format!("{cmdline} {raw}"),
    }
}

fn bare(s: &str) -> bool {
    !s.is_empty()
        && s.bytes()
            .all(|b| b.is_ascii_alphanumeric() || b",._+:@%/=-".contains(&b))
}

pub fn quote(s: &str) -> String {
    if bare(s) {
        s.to_string()
    } else {
        format!("'{}'", s.replace('\'', r"'\''"))
    }
}

pub fn append_args(cmdline: &str, args: &[String]) -> String {
    if args.is_empty() {
        return cmdline.to_string();
    }
    let quoted: Vec<String> = args.iter().map(|a| quote(a)).collect();
    format!("{cmdline} {}", quoted.join(" "))
}

pub fn build(cmdline: &str, raw: Option<&str>, args: &[String]) -> String {
    append_args(&splice(cmdline, raw), args)
}

#[cfg(test)]
mod tests {
    use super::*;

    const CMD: &str = "'/g/run' -x";

    #[test]
    fn splice_table() {
        let cases = [
            (None, CMD.to_string()),
            (Some(""), CMD.to_string()),
            (Some("%command%"), CMD.to_string()),
            (Some("-novid"), format!("{CMD} -novid")),
            (Some("%command% && %command%"), format!("{CMD} && {CMD}")),
            (Some("%COMMAND% -a"), format!("{CMD} %COMMAND% -a")),
            (Some("X=1 %command% -r"), format!("X=1 {CMD} -r")),
            (
                Some("A='b c' %command% $HOME"),
                format!("A='b c' {CMD} $HOME"),
            ),
        ];
        for (raw, want) in cases {
            assert_eq!(splice(CMD, raw), want, "{raw:?}");
        }
    }

    #[test]
    fn quoting() {
        let cases = [
            ("", "''"),
            ("two words", "'two words'"),
            ("$v", "'$v'"),
            ("*", "'*'"),
            ("a'b", r"'a'\''b'"),
            ("n\nl", "'n\nl'"),
            ("-a", "-a"),
            ("key=value", "key=value"),
            ("/p/a,b.c_d+e:f@g%h", "/p/a,b.c_d+e:f@g%h"),
        ];
        for (arg, want) in cases {
            assert_eq!(quote(arg), want, "{arg:?}");
        }
    }

    #[test]
    fn append() {
        let args = vec!["-a".to_string(), "two words".to_string()];
        assert_eq!(append_args("x", &args), "x -a 'two words'");
        assert_eq!(append_args("x", &[]), "x");
        assert_eq!(
            build("x", Some("X=1 %command% -r"), &args),
            "X=1 x -r -a 'two words'"
        );
        assert_eq!(build("x", Some("-novid"), &args), "x -novid -a 'two words'");
        assert_eq!(build("x", None, &args), "x -a 'two words'");
    }
}
