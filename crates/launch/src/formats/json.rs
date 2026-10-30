use serde_json::{Map, Value};

fn merge(base: &mut Map<String, Value>, overlay: &Map<String, Value>) {
    for (key, value) in overlay {
        match (base.get_mut(key), value) {
            (Some(Value::Object(existing)), Value::Object(incoming)) => merge(existing, incoming),
            _ => {
                base.insert(key.clone(), value.clone());
            }
        }
    }
}

fn indent(text: &str) -> String {
    text.lines()
        .find(|l| l.starts_with([' ', '\t']) && !l.trim().is_empty())
        .map(|l| l[..l.len() - l.trim_start().len()].to_string())
        .unwrap_or_else(|| "  ".into())
}

pub fn apply(content: &Value, existing: &[u8]) -> Result<Vec<u8>, String> {
    let (bom, text) = super::utf8(existing, "json file")?;
    let mut root = if text.trim().is_empty() {
        Value::Object(Map::new())
    } else {
        serde_json::from_str(&text).map_err(|e| format!("not valid json: {e}"))?
    };
    let base = root
        .as_object_mut()
        .ok_or("the json file has no object at its root to merge keys into")?;
    let incoming = content.as_object().ok_or("content must be a table")?;
    merge(base, incoming);
    let indent = indent(&text);
    let mut out = Vec::new();
    let formatter = serde_json::ser::PrettyFormatter::with_indent(indent.as_bytes());
    let mut ser = serde_json::Serializer::with_formatter(&mut out, formatter);
    serde::Serialize::serialize(&root, &mut ser).map_err(|e| e.to_string())?;
    out.push(b'\n');
    Ok(super::with_bom(bom, out))
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    fn run(content: serde_json::Value, existing: &str) -> String {
        String::from_utf8(super::apply(&content, existing.as_bytes()).unwrap()).unwrap()
    }

    #[test]
    fn deep_merges_and_keeps_order_and_indent() {
        let out = run(
            json!({"graphics": {"fullscreen": true}}),
            "{\n    \"audio\": 1,\n    \"graphics\": {\n        \"width\": 800\n    }\n}\n",
        );
        assert_eq!(
            out,
            "{\n    \"audio\": 1,\n    \"graphics\": {\n        \"width\": 800,\n        \"fullscreen\": true\n    }\n}\n"
        );
    }

    #[test]
    fn creates_from_nothing_and_refuses_a_non_object_root() {
        assert_eq!(run(json!({"a": 1}), ""), "{\n  \"a\": 1\n}\n");
        assert!(super::apply(&json!({"a": 1}), b"[1]").is_err());
    }

    #[test]
    fn a_utf8_bom_is_kept() {
        let out = super::apply(&json!({"b": 2}), b"\xef\xbb\xbf{\n  \"a\": 1\n}\n").unwrap();
        assert_eq!(out, b"\xef\xbb\xbf{\n  \"a\": 1,\n  \"b\": 2\n}\n");
    }
}
