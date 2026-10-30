use serde_json::Value;

pub fn escape(value: &str) -> String {
    value.replace('\\', "\\\\").replace('"', "\\\"")
}

fn read_quoted(text: &str) -> Option<(String, usize)> {
    let mut out = String::new();
    let mut chars = text.char_indices().skip(1).peekable();
    while let Some((i, c)) = chars.next() {
        match c {
            '\\' => {
                if let Some((_, next)) = chars.next() {
                    out.push(next);
                }
            }
            '"' => return Some((out, i + 1)),
            _ => out.push(c),
        }
    }
    None
}

fn value_name(line: &str) -> Option<String> {
    let stripped = line.trim();
    if stripped.starts_with("@=") {
        return Some("@".into());
    }
    if !stripped.starts_with('"') {
        return None;
    }
    let (name, end) = read_quoted(stripped)?;
    (stripped[end..].starts_with('=')).then_some(name)
}

struct Section {
    path: String,
    header: String,
    body: Vec<String>,
}

fn join_continuations(lines: Vec<String>) -> Vec<String> {
    let mut result = Vec::new();
    let mut buffer: Option<Vec<String>> = None;
    for line in lines {
        if let Some(buf) = &mut buffer {
            let done = !line.ends_with('\\');
            buf.push(line);
            if done {
                result.push(buffer.take().unwrap().join("\n"));
            }
        } else if line.ends_with('\\') {
            buffer = Some(vec![line]);
        } else {
            result.push(line);
        }
    }
    if let Some(buf) = buffer {
        result.push(buf.join("\n"));
    }
    result
}

fn section_path(line: &str) -> Option<String> {
    let inner = line.strip_prefix('[')?;
    let end = inner.find(']')?;
    Some(inner[..end].replace("\\\\", "\\"))
}

fn parse(text: &str) -> (Vec<String>, Vec<Section>) {
    let mut header = Vec::new();
    let mut sections: Vec<Section> = Vec::new();
    let mut raw: Vec<String> = text.split('\n').map(String::from).collect();
    if raw.len() > 1 && raw.last().is_some_and(|l| l.is_empty()) {
        raw.pop();
    }
    for line in join_continuations(raw) {
        if let Some(path) = section_path(&line) {
            sections.push(Section {
                path,
                header: line,
                body: Vec::new(),
            });
        } else if let Some(current) = sections.last_mut() {
            current.body.push(line);
        } else {
            header.push(line);
        }
    }
    (header, sections)
}

fn put_line(section: &mut Section, name: &str, line: String) {
    if let Some(existing) = section
        .body
        .iter_mut()
        .find(|l| value_name(l).is_some_and(|n| n.eq_ignore_ascii_case(name)))
    {
        *existing = line;
        return;
    }
    let mut at = section.body.len();
    while at > 0 && section.body[at - 1].is_empty() {
        at -= 1;
    }
    section.body.insert(at, line);
}

fn apply_with(
    content: &Value,
    existing: &[u8],
    render: &dyn Fn(&str, &Value) -> Result<(String, String), String>,
) -> Result<Vec<u8>, String> {
    let text = if existing.iter().all(|b| b.is_ascii_whitespace()) {
        "WINE REGISTRY Version 2\n\n".to_string()
    } else {
        String::from_utf8(existing.to_vec()).map_err(|_| "the registry file is not utf-8")?
    };
    let (mut header, mut sections) = parse(&text);
    let keys = content
        .as_object()
        .ok_or("content must be a table of registry keys")?;
    for (path, values) in keys {
        let path = path.replace('/', "\\");
        let values = values
            .as_object()
            .ok_or(format!("{path} is not a table of value names"))?;
        let index = match sections
            .iter()
            .position(|s| s.path.eq_ignore_ascii_case(&path))
        {
            Some(i) => i,
            None => {
                let tail = sections
                    .last_mut()
                    .map(|s| &mut s.body)
                    .unwrap_or(&mut header);
                if tail.last().is_none_or(|l| !l.is_empty()) {
                    tail.push(String::new());
                }
                sections.push(Section {
                    path: path.clone(),
                    header: format!("[{}]", path.replace('\\', "\\\\")),
                    body: Vec::new(),
                });
                sections.len() - 1
            }
        };
        for (name, value) in values {
            let (name, line) = render(name, value)?;
            put_line(&mut sections[index], &name, line);
        }
    }
    let mut lines = header;
    for section in sections {
        lines.push(section.header);
        lines.extend(section.body);
    }
    let mut out = lines.join("\n");
    if !out.ends_with('\n') {
        out.push('\n');
    }
    Ok(out.into_bytes())
}

fn dword(n: &serde_json::Number) -> Result<u32, String> {
    n.as_u64()
        .and_then(|v| u32::try_from(v).ok())
        .ok_or_else(|| format!("{n} is outside the 0 to 4294967295 range of a registry dword"))
}

fn render_plain(name: &str, value: &Value) -> Result<(String, String), String> {
    let quoted = if name == "@" {
        "@".to_string()
    } else {
        format!("\"{}\"", escape(name))
    };
    let line = match value {
        Value::Bool(b) => format!("{quoted}=dword:{:08x}", *b as u32),
        Value::Number(n) if n.is_i64() || n.is_u64() => format!("{quoted}=dword:{:08x}", dword(n)?),
        Value::Number(n) => format!("{quoted}=\"{n}\""),
        Value::String(s) => format!("{quoted}=\"{}\"", escape(s)),
        _ => return Err(format!("{name} is not a value a registry file can hold")),
    };
    Ok((name.to_string(), line))
}

pub fn apply(content: &Value, existing: &[u8]) -> Result<Vec<u8>, String> {
    apply_with(content, existing, &render_plain)
}

pub fn unity_hash(key: &str) -> u32 {
    key.bytes()
        .fold(5381u32, |h, b| h.wrapping_mul(33) ^ b as u32)
}

fn hex_bytes(bytes: &[u8]) -> String {
    bytes
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect::<Vec<_>>()
        .join(",")
}

fn render_unity(key: &str, value: &Value) -> Result<(String, String), String> {
    let name = format!("{key}_h{}", unity_hash(key));
    let data = match value {
        Value::Bool(b) => format!("dword:{:08x}", *b as u32),
        Value::Number(n) if n.is_i64() || n.is_u64() => format!(
            "dword:{:08x}",
            n.as_i64()
                .and_then(|v| i32::try_from(v).ok())
                .ok_or_else(|| format!("{key}: {n} does not fit a unity int"))? as u32
        ),
        // unity stores a 32 bit float, so narrowing here stops every launch rewriting the same value
        Value::Number(n) => format!(
            "hex(4):{}",
            hex_bytes(&((n.as_f64().unwrap_or(0.0) as f32) as f64).to_le_bytes())
        ),
        Value::String(s) => format!("hex:{}", hex_bytes(&[s.as_bytes(), &[0]].concat())),
        _ => return Err(format!("{key} is not a value unity prefs can hold")),
    };
    Ok((name.clone(), format!("\"{}\"={data}", escape(&name))))
}

pub fn apply_unity(content: &Value, existing: &[u8]) -> Result<Vec<u8>, String> {
    apply_with(content, existing, &render_unity)
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    const EXISTING: &str = "WINE REGISTRY Version 2\n;; All keys relative to \\\\User\\\\S-1-5-21\n\n[Software\\\\Wine\\\\Direct3D] 1609459200\n#time=1d6c8e0f2\n\"csmt\"=dword:00000000\n\"MaxVersionGL\"=\"3.2\"\n\n[Software\\\\Wine\\\\X11 Driver]\n\"Decorated\"=\"N\"\n";

    fn run(content: serde_json::Value, existing: &str) -> String {
        String::from_utf8(super::apply(&content, existing.as_bytes()).unwrap()).unwrap()
    }

    fn value(text: &str, name: &str) -> Option<String> {
        let prefix = format!("\"{name}\"=");
        text.lines()
            .find_map(|l| l.strip_prefix(&prefix).map(String::from))
    }

    #[test]
    fn merges_and_preserves() {
        let out = run(
            json!({"Software\\Wine\\Direct3D": {"csmt": 1, "renderer": "vulkan"}}),
            EXISTING,
        );
        assert!(out.starts_with(
            "WINE REGISTRY Version 2\n;; All keys relative to \\\\User\\\\S-1-5-21\n"
        ));
        assert!(out.contains("[Software\\\\Wine\\\\Direct3D] 1609459200\n#time=1d6c8e0f2\n"));
        assert_eq!(value(&out, "csmt").as_deref(), Some("dword:00000001"));
        assert_eq!(value(&out, "renderer").as_deref(), Some("\"vulkan\""));
        assert_eq!(value(&out, "MaxVersionGL").as_deref(), Some("\"3.2\""));
        assert_eq!(value(&out, "Decorated").as_deref(), Some("\"N\""));
        assert_eq!(out.matches("\"csmt\"=").count(), 1);
    }

    #[test]
    fn new_section_and_new_file() {
        let out = run(json!({"Software/Wine/NewKey": {"foo": "bar"}}), EXISTING);
        assert!(out.contains("\n\n[Software\\\\Wine\\\\NewKey]\n\"foo\"=\"bar\"\n"));
        let out = run(json!({"Software\\Test": {"a": 255}}), "");
        assert_eq!(
            out,
            "WINE REGISTRY Version 2\n\n[Software\\\\Test]\n\"a\"=dword:000000ff\n"
        );
    }

    #[test]
    fn strings_escape_and_round_trip() {
        let raw = "C:\\Games\\\"save\"";
        let out = run(json!({"Software\\Test": {"path": raw}}), "");
        assert_eq!(
            value(&out, "path").as_deref(),
            Some("\"C:\\\\Games\\\\\\\"save\\\"\"")
        );
        assert_eq!(run(json!({"Software\\Test": {"path": raw}}), &out), out);
    }

    #[test]
    fn case_insensitive_match_default_value_and_dword_range() {
        let out = run(json!({"software\\wine\\direct3d": {"CSMT": 1}}), EXISTING);
        assert_eq!(out.matches("[Software\\\\Wine\\\\Direct3D]").count(), 1);
        assert!(!out.contains("direct3d]"));
        assert_eq!(value(&out, "CSMT").as_deref(), Some("dword:00000001"));
        assert!(!out.contains("\"csmt\"="));
        let out = run(
            json!({"Software\\Test": {"@": "x"}}),
            "WINE REGISTRY Version 2\n\n[Software\\\\Test]\n@=\"old\"\n",
        );
        assert!(out.contains("\n@=\"x\"\n"));
        assert!(!out.contains("old"));
        assert!(super::apply(&json!({"Software\\Test": {"a": 4294967296u64}}), b"").is_err());
        assert!(super::apply(&json!({"Software\\Test": {"a": -1}}), b"").is_err());
        assert!(super::apply_unity(&json!({"Software\\T\\P": {"a": -1}}), b"").is_ok());
        assert!(super::apply_unity(&json!({"Software\\T\\P": {"a": 4294967296u64}}), b"").is_err());
    }

    #[test]
    fn a_wrapped_value_survives_and_a_sibling_is_set() {
        let existing = "WINE REGISTRY Version 2\n\n[Software\\\\VRChat\\\\VRChat]\n\"Blob_h1518735675\"=hex:49,61,49,5a,\\\n  4a,2f,00\n\"Keep_h123\"=dword:00000005\n";
        let out = run(json!({"Software\\VRChat\\VRChat": {"Extra": 7}}), existing);
        assert!(out.contains("\"Blob_h1518735675\"=hex:49,61,49,5a,\\\n  4a,2f,00\n"));
        assert_eq!(out.matches("4a,2f,00").count(), 1);
        assert_eq!(value(&out, "Keep_h123").as_deref(), Some("dword:00000005"));
        assert_eq!(value(&out, "Extra").as_deref(), Some("dword:00000007"));
    }

    #[test]
    fn unity_hash_matches_what_unity_writes() {
        assert_eq!(
            super::unity_hash("PersonalMirror.FaceMirrorPosX"),
            1476246502
        );
        assert_eq!(super::unity_hash("FaceMirrorOwner"), 1560350044);
    }

    #[test]
    fn unity_values_are_encoded_by_type() {
        let content = json!({"Software\\Co\\Prod": {"Count": 255, "On": true, "Scale": 0.5, "Gate": 0.002, "Owner": "abc", "Whole": 1.0}});
        let out = String::from_utf8(super::apply_unity(&content, b"").unwrap()).unwrap();
        let h = super::unity_hash;
        assert_eq!(
            value(&out, &format!("Count_h{}", h("Count"))).as_deref(),
            Some("dword:000000ff")
        );
        assert_eq!(
            value(&out, &format!("On_h{}", h("On"))).as_deref(),
            Some("dword:00000001")
        );
        assert_eq!(
            value(&out, &format!("Scale_h{}", h("Scale"))).as_deref(),
            Some("hex(4):00,00,00,00,00,00,e0,3f")
        );
        assert_eq!(
            value(&out, &format!("Gate_h{}", h("Gate"))).as_deref(),
            Some("hex(4):00,00,00,e0,4d,62,60,3f")
        );
        assert_eq!(
            value(&out, &format!("Owner_h{}", h("Owner"))).as_deref(),
            Some("hex:61,62,63,00")
        );
        assert_eq!(
            value(&out, &format!("Whole_h{}", h("Whole"))).as_deref(),
            Some("hex(4):00,00,00,00,00,00,f0,3f")
        );
        assert_eq!(
            super::apply_unity(&content, out.as_bytes()).unwrap(),
            out.as_bytes()
        );
    }
}
