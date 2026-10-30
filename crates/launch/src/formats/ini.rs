use std::collections::BTreeMap;

use serde_json::Value;

use super::text::{self, Line};

struct Entry {
    indent: usize,
    key_end: usize,
    value_start: usize,
}

fn comment(body: &str) -> bool {
    matches!(body.trim_start().chars().next(), Some(';') | Some('#'))
}

fn section(body: &str) -> Option<String> {
    let trimmed = body.trim_start();
    let inner = trimmed.strip_prefix('[')?;
    let end = inner.find(']')?;
    let rest = inner[end + 1..].trim_start();
    if !(rest.is_empty() || rest.starts_with(';') || rest.starts_with('#')) {
        return None;
    }
    Some(inner[..end].trim().to_string())
}

fn entry(body: &str) -> Option<Entry> {
    let indent = body.len() - body.trim_start().len();
    let rest = &body[indent..];
    let first = rest.chars().next()?;
    if first == '=' || first == ';' || first == '#' {
        return None;
    }
    let eq = rest.find('=')?;
    let key = rest[..eq].trim_end();
    if key.is_empty() {
        return None;
    }
    let after = &rest[eq + 1..];
    let value_start = indent + eq + 1 + (after.len() - after.trim_start().len());
    Some(Entry {
        indent,
        key_end: indent + key.len(),
        value_start,
    })
}

fn key_of<'a>(body: &'a str, e: &Entry) -> &'a str {
    &body[e.indent..e.key_end]
}

fn renderings(section: &str, key: &str, value: &Value) -> Result<Vec<String>, String> {
    if let Value::Array(items) = value {
        return items
            .iter()
            .map(|v| renderings(section, key, v))
            .collect::<Result<Vec<_>, _>>()
            .map(|v| v.concat());
    }
    let rendered = text::scalar(value).ok_or(format!(
        "{section}.{key} is not a value an ini file can hold"
    ))?;
    // a line ending in a value splits the line, and the halves grow the file on every run
    if rendered.contains(['\n', '\r']) {
        return Err(format!("{section}.{key} cannot be written as an ini value"));
    }
    Ok(vec![rendered])
}

fn check(line: &str, section: &str, key: &str, rendered: &str) -> Result<(), String> {
    let ok = entry(line).is_some_and(|e| {
        key_of(line, &e).eq_ignore_ascii_case(key) && &line[e.value_start..] == rendered
    });
    ok.then_some(())
        .ok_or(format!("{section}.{key} cannot be written as an ini value"))
}

type Index = BTreeMap<(String, String), Vec<usize>>;

fn scan(lines: &[Line]) -> Result<(Index, BTreeMap<String, usize>), String> {
    let mut entries: Index = BTreeMap::new();
    let mut section_end = BTreeMap::new();
    let mut current = String::new();
    let mut previous_indent: Option<usize> = None;
    let mut structured = false;
    let mut content = false;
    for (index, line) in lines.iter().enumerate() {
        let body = &line.body;
        if body.trim().is_empty() || comment(body) {
            continue;
        }
        content = true;
        if let Some(name) = section(body) {
            current = name.to_ascii_lowercase();
            section_end.insert(current.clone(), index);
            previous_indent = None;
            structured = true;
            continue;
        }
        // an unparsed header would put the keys under it into the section above
        if body.trim_start().starts_with('[') {
            return Err(format!(
                "{} is not a section header we can edit around",
                body.trim()
            ));
        }
        section_end.insert(current.clone(), index);
        let Some(e) = entry(body) else {
            previous_indent = None;
            continue;
        };
        // a deeper indented line continues the value above it, so it is not ours to edit
        if previous_indent.is_some_and(|p| e.indent > p) {
            return Err(format!("{} continues the line above it", body.trim()));
        }
        previous_indent = Some(e.indent);
        structured = true;
        entries
            .entry((current.clone(), key_of(body, &e).to_ascii_lowercase()))
            .or_default()
            .push(index);
    }
    if !structured && content {
        return Err("the file has no ini sections or keys to merge into".into());
    }
    Ok((entries, section_end))
}

pub fn apply(content: &Value, existing: &[u8]) -> Result<Vec<u8>, String> {
    let decoded = text::decode(existing)?;
    let mut lines = text::split(&decoded.body);
    let newline = text::newline(&lines);
    let (entries, section_end) = scan(&lines)?;
    let sections = content
        .as_object()
        .ok_or("content must be a table of sections")?;

    let mut dropped = std::collections::BTreeSet::new();
    let mut inserted: BTreeMap<usize, Vec<String>> = BTreeMap::new();
    let mut new_sections: Vec<(String, Vec<String>)> = Vec::new();

    for (section_name, values) in sections {
        let values = values
            .as_object()
            .ok_or(format!("{section_name} is not a table of ini keys"))?;
        for (key, value) in values {
            let rendered = renderings(section_name, key, value)?;
            let found = entries
                .get(&(section_name.to_ascii_lowercase(), key.to_ascii_lowercase()))
                .cloned()
                .unwrap_or_default();
            for (position, rendered) in rendered.iter().enumerate() {
                if let Some(&index) = found.get(position) {
                    let body = &lines[index].body;
                    let e = entry(body).expect("indexed entry parses");
                    let updated = format!("{}{}", &body[..e.value_start], rendered);
                    check(&updated, section_name, key, rendered)?;
                    lines[index].body = updated;
                    continue;
                }
                let line = format!("{key}={rendered}");
                check(&line, section_name, key, rendered)?;
                if let Some(&last) = found.last() {
                    inserted.entry(last).or_default().push(line);
                } else if let Some(&end) = section_end.get(&section_name.to_ascii_lowercase()) {
                    inserted.entry(end).or_default().push(line);
                } else {
                    // a header that does not read back never matches, so the section would be appended again every run
                    if section(&format!("[{section_name}]")).as_deref() != Some(section_name) {
                        return Err(format!(
                            "{section_name} cannot be written as an ini section"
                        ));
                    }
                    match new_sections
                        .iter_mut()
                        .find(|(s, _)| s.eq_ignore_ascii_case(section_name))
                    {
                        Some((_, added)) => added.push(line),
                        None => new_sections.push((section_name.clone(), vec![line])),
                    }
                }
            }
            dropped.extend(found.iter().skip(rendered.len()).copied());
        }
    }

    let mut out: Vec<String> = Vec::new();
    let terminate = |out: &mut Vec<String>| {
        if let Some(last) = out.last_mut() {
            if !last.ends_with(['\n', '\r']) {
                last.push_str(&newline);
            }
        }
    };
    for (index, line) in lines.iter().enumerate() {
        if !dropped.contains(&index) {
            out.push(format!("{}{}", line.body, line.ending));
        }
        if let Some(extra) = inserted.get(&index) {
            terminate(&mut out);
            out.extend(extra.iter().map(|l| format!("{l}{newline}")));
        }
    }
    for (name, added) in new_sections {
        terminate(&mut out);
        if !out.is_empty() {
            out.push(newline.clone());
        }
        out.push(format!("[{name}]{newline}"));
        out.extend(added.iter().map(|l| format!("{l}{newline}")));
    }
    Ok(text::encode(&decoded, &out.concat()))
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    fn run(content: serde_json::Value, existing: &str) -> String {
        String::from_utf8(super::apply(&content, existing.as_bytes()).unwrap()).unwrap()
    }

    #[test]
    fn duplicate_keys_are_kept_and_the_named_one_replaced() {
        let out = run(
            json!({"Engine.Console": {"ConsoleKey": "F9"}}),
            "[Engine.Console]\nConsoleKey = Tilde\nManualAutoCompleteList = Open\nManualAutoCompleteList = Exit\n",
        );
        assert_eq!(
            out,
            "[Engine.Console]\nConsoleKey = F9\nManualAutoCompleteList = Open\nManualAutoCompleteList = Exit\n"
        );
    }

    #[test]
    fn a_replaced_key_ends_up_with_one_occurrence() {
        assert_eq!(
            run(
                json!({"Display": {"Width": 1920}}),
                "[Display]\nWidth = 800\nWidth = 1024\n"
            ),
            "[Display]\nWidth = 1920\n"
        );
    }

    #[test]
    fn a_list_writes_one_line_per_item_and_is_stable() {
        let first = run(json!({"A": {"+K": ["C", "D", "E"]}}), "[A]\n+K=A\n+K=B\n");
        assert_eq!(first, "[A]\n+K=C\n+K=D\n+K=E\n");
        assert_eq!(run(json!({"A": {"+K": ["C", "D", "E"]}}), &first), first);
    }

    #[test]
    fn comments_order_and_crlf_survive() {
        let out = run(
            json!({"Display": {"Width": 1920}}),
            "; keep me\r\n[Display]\r\n; and me\r\nWidth = 800\r\nHeight = 600\r\n",
        );
        assert_eq!(
            out,
            "; keep me\r\n[Display]\r\n; and me\r\nWidth = 1920\r\nHeight = 600\r\n"
        );
    }

    #[test]
    fn new_keys_and_sections_are_appended() {
        let out = run(
            json!({"Display": {"Height": 600}, "Audio": {"Volume": 50}}),
            "[Display]\nWidth = 800",
        );
        assert_eq!(
            out,
            "[Display]\nWidth = 800\nHeight=600\n\n[Audio]\nVolume=50\n"
        );
    }

    #[test]
    fn a_header_with_a_comment_keeps_its_own_keys() {
        let out = run(
            json!({"Audio": {"Volume": 80}}),
            "[Audio]\nVolume=50\n[Video] ; my note\nVolume=100\n",
        );
        assert_eq!(out, "[Audio]\nVolume=80\n[Video] ; my note\nVolume=100\n");
    }

    #[test]
    fn padded_header_and_colon_key_are_edited_in_place() {
        assert_eq!(
            run(
                json!({"Video": {"Width": 1920}}),
                "[ Video ]\nWidth = 800\n"
            ),
            "[ Video ]\nWidth = 1920\n"
        );
        assert_eq!(
            run(json!({"A": {"HTTP:Proxy": 2}}), "[A]\nHTTP:Proxy=1\n"),
            "[A]\nHTTP:Proxy=2\n"
        );
    }

    #[test]
    fn utf16_in_and_out() {
        let existing: Vec<u8> = "[A]\nc=1\n"
            .encode_utf16()
            .flat_map(|u| u.to_le_bytes())
            .collect();
        let out = super::apply(&json!({"A": {"b": 2}}), &existing).unwrap();
        let units: Vec<u16> = out
            .chunks(2)
            .map(|c| u16::from_le_bytes([c[0], c[1]]))
            .collect();
        assert_eq!(String::from_utf16(&units).unwrap(), "[A]\nc=1\nb=2\n");
        let with_bom = [&[0xff, 0xfe][..], &existing].concat();
        let out = super::apply(&json!({"A": {"b": 2}}), &with_bom).unwrap();
        assert!(out.starts_with(&[0xff, 0xfe]));
    }

    #[test]
    fn section_and_key_match_regardless_of_case() {
        assert_eq!(
            run(
                json!({"display": {"WIDTH": 1920}}),
                "[Display]\nWidth = 800\n"
            ),
            "[Display]\nWidth = 1920\n"
        );
        assert_eq!(
            run(
                json!({"display": {"Height": 600}}),
                "[Display]\nWidth = 800\n"
            ),
            "[Display]\nWidth = 800\nHeight=600\n"
        );
    }

    #[test]
    fn a_file_of_only_comments_gains_a_section() {
        assert_eq!(
            run(json!({"Display": {"Width": 1920}}), "; set Width\n"),
            "; set Width\n\n[Display]\nWidth=1920\n"
        );
    }

    #[test]
    fn every_line_survives_unless_replaced() {
        let existing = "; c\n[A]\nk=1\nj=2\n\n[B]\n; d\nk=3\n";
        let out = run(json!({"A": {"k": 9}}), existing);
        let kept: Vec<&str> = existing.lines().filter(|l| *l != "k=1").collect();
        for line in kept {
            assert!(out.lines().any(|l| l == line), "{line} lost");
        }
    }

    #[test]
    fn refusals() {
        assert!(
            super::apply(
                &json!({" Video ": {"Width": 1}}),
                b"[Display]\nWidth = 800\n"
            )
            .is_err()
        );
        assert!(super::apply(&json!({"A": {"b": "x\ny"}}), b"[A]\nc=1\n").is_err());
        assert!(super::apply(&json!({"A": {"b": {"c": 1}}}), b"[A]\nc=1\n").is_err());
        assert!(super::apply(&json!({"A": {"b": 1}}), b"[A]\nc=1\n  d=2\n").is_err());
        assert!(super::apply(&json!({"A": {"b": 1}}), b"not ini at all\n").is_err());
    }
}
