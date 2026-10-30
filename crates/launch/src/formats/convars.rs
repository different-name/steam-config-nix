use serde_json::Value;

fn leading_token(line: &str) -> Option<&str> {
    let stripped = line.trim_start();
    if stripped.is_empty() || stripped.starts_with("//") {
        return None;
    }
    stripped.split_whitespace().next()
}

fn split_value(rest: &str) -> (&str, &str) {
    if rest.starts_with('"') {
        let end = rest[1..].find('"').map(|i| i + 2).unwrap_or(rest.len());
        return rest.split_at(end);
    }
    let mut end = 0;
    for (i, c) in rest.char_indices() {
        if c.is_whitespace() || c == ';' || rest[i..].starts_with("//") {
            break;
        }
        end = i + c.len_utf8();
    }
    rest.split_at(end)
}

fn render(value: &Value) -> Result<String, String> {
    match value {
        Value::Bool(b) => Ok(if *b { "1".into() } else { "0".into() }),
        Value::Number(n) => Ok(n.to_string()),
        Value::String(s) if s.contains(['"', '\n', '\r']) => {
            Err("a console variable value cannot hold quotes or line breaks".into())
        }
        Value::String(s) => Ok(s.clone()),
        _ => Err("a console variable takes a string, number or boolean".into()),
    }
}

fn rewrite(line: &str, new_value: &str) -> String {
    let indent = &line[..line.len() - line.trim_start().len()];
    let stripped = &line[indent.len()..];
    let name = stripped.split_whitespace().next().unwrap_or("");
    let after = &stripped[name.len()..];
    let sep = &after[..after.len() - after.trim_start().len()];
    let (_, rest) = split_value(&after[sep.len()..]);
    let sep = if sep.is_empty() { " " } else { sep };
    format!("{indent}{name}{sep}\"{new_value}\"{rest}")
}

pub fn apply(content: &Value, existing: &[u8]) -> Result<Vec<u8>, String> {
    let (bom, text) = super::utf8(existing, "config")?;
    let newline = if text.contains("\r\n") { "\r\n" } else { "\n" };
    let mut lines: Vec<String> = text
        .split('\n')
        .map(|l| l.strip_suffix('\r').unwrap_or(l).to_string())
        .collect();
    if lines.last().is_some_and(|l| l.is_empty()) {
        lines.pop();
    }
    let vars = content
        .as_object()
        .ok_or("content must be a table of console variables")?;
    for (name, value) in vars {
        let rendered = render(value).map_err(|e| format!("{name}: {e}"))?;
        let last = lines
            .iter()
            .rposition(|l| leading_token(l).is_some_and(|t| t.eq_ignore_ascii_case(name)));
        match last {
            Some(i) => lines[i] = rewrite(&lines[i], &rendered),
            None => lines.push(format!("{name} \"{rendered}\"")),
        }
    }
    let mut out = lines.join(newline);
    if !out.is_empty() {
        out.push_str(newline);
    }
    Ok(super::with_bom(bom, out.into_bytes()))
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    fn run(content: serde_json::Value, existing: &str) -> String {
        String::from_utf8(super::apply(&content, existing.as_bytes()).unwrap()).unwrap()
    }

    #[test]
    fn updates_in_place_and_keeps_the_rest() {
        let out = run(
            json!({"sensitivity": 1.8, "fps_max": 300}),
            "// header\nbind \"1\" \"slot1\"\nalias \"tr\" \"toggle cl_crosshair_recoil 1 0\"\nsensitivity \"2.055\"\nfps_max 400\n",
        );
        assert_eq!(
            out,
            "// header\nbind \"1\" \"slot1\"\nalias \"tr\" \"toggle cl_crosshair_recoil 1 0\"\nsensitivity \"1.8\"\nfps_max \"300\"\n"
        );
    }

    #[test]
    fn appends_when_absent_and_ignores_alias_bodies() {
        assert_eq!(
            run(json!({"fps_max": 400}), "sensitivity \"2\"\n"),
            "sensitivity \"2\"\nfps_max \"400\"\n"
        );
        let out = run(
            json!({"cl_crosshair_recoil": true}),
            "alias \"tr\" \"cl_crosshair_recoil 1\"\n",
        );
        assert_eq!(
            out,
            "alias \"tr\" \"cl_crosshair_recoil 1\"\ncl_crosshair_recoil \"1\"\n"
        );
    }

    #[test]
    fn comments_case_duplicates_and_crlf() {
        assert_eq!(
            run(
                json!({"cl_crosshairsize": 3}),
                "cl_crosshairsize \"2\" // size\n"
            ),
            "cl_crosshairsize \"3\" // size\n"
        );
        assert_eq!(
            run(
                json!({"cl_crosshair_recoil": true}),
                "Cl_Crosshair_Recoil false\n"
            ),
            "Cl_Crosshair_Recoil \"1\"\n"
        );
        assert_eq!(
            run(json!({"fps_max": 300}), "fps_max \"60\"\nfps_max \"120\"\n"),
            "fps_max \"60\"\nfps_max \"300\"\n"
        );
        assert_eq!(
            run(
                json!({"fps_max": 120}),
                "sensitivity \"2\"\r\nfps_max \"60\"\r\n"
            ),
            "sensitivity \"2\"\r\nfps_max \"120\"\r\n"
        );
        assert_eq!(
            run(json!({"fps_max": 400, "sensitivity": 1.5}), ""),
            "fps_max \"400\"\nsensitivity \"1.5\"\n"
        );
    }

    #[test]
    fn bare_names_semicolons_boms_and_bad_values() {
        assert_eq!(
            run(json!({"fps_max": 300}), "fps_max\n"),
            "fps_max \"300\"\n"
        );
        assert_eq!(
            run(json!({"fps_max": 300}), "fps_max 60; sensitivity 2\n"),
            "fps_max \"300\"; sensitivity 2\n"
        );
        assert_eq!(
            super::apply(&json!({"fps_max": 300}), b"\xef\xbb\xbffps_max 60\n").unwrap(),
            b"\xef\xbb\xbffps_max \"300\"\n"
        );
        assert!(super::apply(&json!({"name": "a\nb"}), b"").is_err());
        assert!(super::apply(&json!({"name": "a\"b"}), b"").is_err());
    }
}
