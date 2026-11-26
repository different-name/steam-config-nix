use serde_json::Value;
pub use steam_config_vdf::text::{Node, dump, parse};

fn set_all(root: &mut Node, content: &Value, prefix: &mut Vec<String>) -> Result<(), String> {
    let table = content.as_object().ok_or("content must be a table")?;
    for (key, value) in table {
        prefix.push(key.clone());
        match value {
            Value::Object(_) => set_all(root, value, prefix)?,
            Value::String(s) => {
                root.set_path(&prefix.iter().map(String::as_str).collect::<Vec<_>>(), s)
            }
            Value::Number(n) => root.set_path(
                &prefix.iter().map(String::as_str).collect::<Vec<_>>(),
                &n.to_string(),
            ),
            Value::Bool(b) => root.set_path(
                &prefix.iter().map(String::as_str).collect::<Vec<_>>(),
                if *b { "1" } else { "0" },
            ),
            _ => {
                return Err(format!(
                    "{} is not a value a keyvalues file can hold",
                    prefix.join(".")
                ));
            }
        }
        prefix.pop();
    }
    Ok(())
}

pub fn apply(content: &Value, existing: &[u8]) -> Result<Vec<u8>, String> {
    let (bom, text) = super::utf8(existing, "keyvalues file")?;
    let mut root = if text.trim().is_empty() {
        Node::block("")
    } else {
        parse(&text)?
    };
    set_all(&mut root, content, &mut Vec::new())?;
    Ok(super::with_bom(bom, dump(&root).into_bytes()))
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    fn run(content: serde_json::Value, existing: &str) -> String {
        String::from_utf8(super::apply(&content, existing.as_bytes()).unwrap()).unwrap()
    }

    #[test]
    fn merges_into_a_block_and_keeps_the_rest() {
        let out = run(
            json!({"Settings": {"Volume": 100, "Fullscreen": 1}}),
            "\"Settings\"\n{\n\t\"Width\"\t\t\"1920\"\n\t\"Volume\"\t\t\"50\"\n}\n",
        );
        assert_eq!(
            out,
            "\"Settings\"\n{\n\t\"Width\"\t\t\"1920\"\n\t\"Volume\"\t\t\"100\"\n\t\"Fullscreen\"\t\t\"1\"\n}\n"
        );
    }

    #[test]
    fn creates_nested_blocks_and_is_stable() {
        let out = run(json!({"a": {"b": {"c": "x"}}}), "");
        assert_eq!(out, "\"a\"\n{\n\t\"b\"\n\t{\n\t\t\"c\"\t\t\"x\"\n\t}\n}\n");
        assert_eq!(run(json!({"a": {"b": {"c": "x"}}}), &out), out);
    }

    #[test]
    fn parses_comments_unquoted_tokens_and_escapes() {
        let root = super::parse("// top\nlibraryfolders\n{\n\t\"0\" { path \"/a b\" } // note\n\t\"1\"\t\"x\\\"y\"\n}\n").unwrap();
        let folders = root.find("LibraryFolders").unwrap();
        assert_eq!(
            folders
                .find("0")
                .unwrap()
                .find("path")
                .unwrap()
                .value
                .as_deref(),
            Some("/a b")
        );
        assert_eq!(folders.find("1").unwrap().value.as_deref(), Some("x\"y"));
        assert!(super::parse("\"a\" {").is_err());
        assert!(super::parse("\"a\"").is_err());
    }

    #[test]
    fn a_utf8_bom_is_kept() {
        let out = super::apply(&json!({"a": "1"}), b"\xef\xbb\xbf\"a\"\t\t\"0\"\n").unwrap();
        assert!(out.starts_with(b"\xef\xbb\xbf\"a\""));
        assert!(out.ends_with(b"\"1\"\n"));
    }
}
