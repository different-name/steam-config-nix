use serde_json::{Map, Value};

#[derive(Debug, PartialEq, Clone)]
pub struct Node {
    pub name: String,
    pub value: Option<String>,
    pub children: Option<Vec<Node>>,
}

impl Node {
    pub fn block(name: &str) -> Self {
        Node {
            name: name.into(),
            value: None,
            children: Some(Vec::new()),
        }
    }

    pub fn children(&self) -> impl Iterator<Item = &Node> {
        self.children.iter().flatten()
    }

    pub fn find(&self, name: &str) -> Option<&Node> {
        self.children().find(|c| c.name.eq_ignore_ascii_case(name))
    }

    pub fn find_mut(&mut self, name: &str) -> Option<&mut Node> {
        self.children
            .as_mut()?
            .iter_mut()
            .find(|c| c.name.eq_ignore_ascii_case(name))
    }

    pub fn find_path(&self, path: &[&str]) -> Option<&Node> {
        let (leaf, blocks) = path.split_last()?;
        let mut node = self;
        for name in blocks {
            node = node
                .children()
                .find(|c| c.name.eq_ignore_ascii_case(name) && c.children.is_some())?;
        }
        node.find(leaf)
    }

    pub fn find_path_mut(&mut self, path: &[&str]) -> Option<&mut Node> {
        let (leaf, blocks) = path.split_last()?;
        let mut node = self;
        for name in blocks {
            node = node
                .children
                .as_mut()?
                .iter_mut()
                .find(|c| c.name.eq_ignore_ascii_case(name) && c.children.is_some())?;
        }
        node.find_mut(leaf)
    }

    pub fn remove(&mut self, name: &str) -> bool {
        let Some(children) = self.children.as_mut() else {
            return false;
        };
        let before = children.len();
        children.retain(|c| !c.name.eq_ignore_ascii_case(name));
        children.len() != before
    }

    pub fn to_json(&self) -> Value {
        match &self.children {
            Some(children) => {
                let mut map = Map::new();
                for child in children {
                    map.insert(child.name.clone(), child.to_json());
                }
                Value::Object(map)
            }
            None => Value::String(self.value.clone().unwrap_or_default()),
        }
    }

    pub fn from_json(name: &str, value: &Value) -> Node {
        match value {
            Value::Object(map) => Node {
                name: name.into(),
                value: None,
                children: Some(map.iter().map(|(k, v)| Node::from_json(k, v)).collect()),
            },
            Value::String(s) => Node {
                name: name.into(),
                value: Some(s.clone()),
                children: None,
            },
            other => Node {
                name: name.into(),
                value: Some(other.to_string()),
                children: None,
            },
        }
    }

    pub fn set_path(&mut self, path: &[&str], value: &str) {
        let (leaf, blocks) = path.split_last().expect("a path has a leaf");
        let mut node = self;
        for name in blocks {
            let children = node.children.get_or_insert_with(Vec::new);
            let index = match children
                .iter()
                .position(|c| c.name.eq_ignore_ascii_case(name) && c.children.is_some())
            {
                Some(i) => i,
                None => {
                    children.push(Node::block(name));
                    children.len() - 1
                }
            };
            node = &mut children[index];
        }
        let children = node.children.get_or_insert_with(Vec::new);
        match children
            .iter_mut()
            .find(|c| c.name.eq_ignore_ascii_case(leaf) && c.children.is_none())
        {
            Some(existing) => existing.value = Some(value.into()),
            None => children.push(Node {
                name: leaf.to_string(),
                value: Some(value.into()),
                children: None,
            }),
        }
    }
}

enum Token {
    Str(String),
    Open,
    Close,
}

fn tokenize(text: &str) -> Result<Vec<Token>, String> {
    let mut tokens = Vec::new();
    let chars: Vec<char> = text.chars().collect();
    let mut i = 0;
    let mut line = 1;
    while i < chars.len() {
        let c = chars[i];
        match c {
            '\n' => {
                line += 1;
                i += 1;
            }
            ' ' | '\t' | '\r' => i += 1,
            '/' if chars.get(i + 1) == Some(&'/') => {
                while i < chars.len() && chars[i] != '\n' {
                    i += 1;
                }
            }
            '{' => {
                tokens.push(Token::Open);
                i += 1;
            }
            '}' => {
                tokens.push(Token::Close);
                i += 1;
            }
            '"' => {
                let mut out = String::new();
                i += 1;
                loop {
                    let Some(&c) = chars.get(i) else {
                        return Err(format!("unterminated string (line {line})"));
                    };
                    i += 1;
                    match c {
                        '"' => break,
                        '\\' => {
                            let next = chars.get(i).copied();
                            i += 1;
                            let unescaped = match next {
                                Some('n') => '\n',
                                Some('t') => '\t',
                                Some('r') => '\r',
                                Some('"') => '"',
                                Some('\\') => '\\',
                                Some(other) => {
                                    out.push('\\');
                                    other
                                }
                                None => return Err(format!("unterminated string (line {line})")),
                            };
                            out.push(unescaped);
                        }
                        '\n' => {
                            line += 1;
                            out.push(c);
                        }
                        _ => out.push(c),
                    }
                }
                tokens.push(Token::Str(out));
            }
            _ => {
                let start = i;
                while i < chars.len() && !" \t\r\n{}\"".contains(chars[i]) {
                    i += 1;
                }
                tokens.push(Token::Str(chars[start..i].iter().collect()));
            }
        }
    }
    Ok(tokens)
}

pub fn parse(text: &str) -> Result<Node, String> {
    let mut root = Node::block("");
    let mut stack: Vec<Node> = Vec::new();
    let mut pending: Option<String> = None;
    for token in tokenize(text)? {
        let top = stack.last_mut().unwrap_or(&mut root);
        match (pending.take(), token) {
            (None, Token::Str(s)) => pending = Some(s),
            (None, Token::Close) => {
                let done = stack.pop().ok_or("unexpected '}'")?;
                stack
                    .last_mut()
                    .unwrap_or(&mut root)
                    .children
                    .get_or_insert_with(Vec::new)
                    .push(done);
            }
            (None, Token::Open) => return Err("unexpected '{'".into()),
            (Some(key), Token::Str(value)) => {
                top.children.get_or_insert_with(Vec::new).push(Node {
                    name: key,
                    value: Some(value),
                    children: None,
                })
            }
            (Some(key), Token::Open) => stack.push(Node::block(&key)),
            (Some(key), Token::Close) => return Err(format!("key {key:?} has no value")),
        }
    }
    if let Some(key) = pending {
        return Err(format!("key {key:?} has no value"));
    }
    if let Some(open) = stack.last() {
        return Err(format!("unclosed block {:?}", open.name));
    }
    Ok(root)
}

// steam writes newlines inside values literally, an escaped form does not round trip
fn escape(value: &str) -> String {
    value.replace('\\', "\\\\").replace('"', "\\\"")
}

fn write(node: &Node, depth: usize, out: &mut String) {
    let indent = "\t".repeat(depth);
    match &node.children {
        Some(children) => {
            out.push_str(&format!("{indent}\"{}\"\n{indent}{{\n", escape(&node.name)));
            for child in children {
                write(child, depth + 1, out);
            }
            out.push_str(&format!("{indent}}}\n"));
        }
        None => out.push_str(&format!(
            "{indent}\"{}\"\t\t\"{}\"\n",
            escape(&node.name),
            escape(node.value.as_deref().unwrap_or(""))
        )),
    }
}

pub fn dump(root: &Node) -> String {
    let mut out = String::new();
    for child in root.children() {
        write(child, 0, &mut out);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::{Node, dump, parse};
    use serde_json::json;

    const SAMPLE: &str = "\"InstallConfigStore\"\n{\n\t\"Software\"\n\t{\n\t\t\"Valve\"\n\t\t{\n\t\t\t\"Steam\"\n\t\t\t{\n\t\t\t\t\"CompatToolMapping\"\n\t\t\t\t{\n\t\t\t\t\t\"0\"\n\t\t\t\t\t{\n\t\t\t\t\t\t\"name\"\t\t\"proton_experimental\"\n\t\t\t\t\t\t\"config\"\t\t\"\"\n\t\t\t\t\t\t\"priority\"\t\t\"75\"\n\t\t\t\t\t}\n\t\t\t\t}\n\t\t\t\t\"AutoUpdateWindowEnabled\"\t\t\"0\"\n\t\t\t}\n\t\t}\n\t}\n}\n";

    fn leaf(name: &str, value: &str) -> Node {
        Node {
            name: name.into(),
            value: Some(value.into()),
            children: None,
        }
    }

    #[test]
    fn parses_nested_blocks_and_leaves() {
        let root = parse(SAMPLE).unwrap();
        let path = [
            "InstallConfigStore",
            "Software",
            "Valve",
            "Steam",
            "CompatToolMapping",
            "0",
            "name",
        ];
        assert_eq!(
            root.find_path(&path).unwrap().value.as_deref(),
            Some("proton_experimental")
        );
    }

    #[test]
    fn dumps_matches_steam_style() {
        assert_eq!(dump(&parse(SAMPLE).unwrap()), SAMPLE);
    }

    #[test]
    fn round_trip_is_stable() {
        let root = parse(SAMPLE).unwrap();
        assert_eq!(parse(&dump(&root)).unwrap(), root);
    }

    #[test]
    fn duplicate_keys_and_order_are_preserved() {
        let text = "\"Root\"\n{\n\t\"A\"\t\t\"1\"\n\t\"A\"\t\t\"2\"\n\t\"B\"\t\t\"3\"\n}\n";
        let root = parse(text).unwrap();
        let pairs: Vec<(&str, Option<&str>)> = root
            .find("Root")
            .unwrap()
            .children()
            .map(|n| (n.name.as_str(), n.value.as_deref()))
            .collect();
        assert_eq!(
            pairs,
            vec![("A", Some("1")), ("A", Some("2")), ("B", Some("3"))]
        );
        assert_eq!(dump(&root), text);
    }

    #[test]
    fn find_is_case_insensitive() {
        let root = parse("\"Root\"\n{\n\t\"Apps\"\t\t\"x\"\n}\n").unwrap();
        assert_eq!(
            root.find_path(&["root", "APPS"]).unwrap().value.as_deref(),
            Some("x")
        );
    }

    #[test]
    fn case_is_preserved_on_write() {
        let text = "\"RoOt\"\n{\n\t\"ApPs\"\t\t\"x\"\n}\n";
        assert_eq!(dump(&parse(text).unwrap()), text);
    }

    #[test]
    fn escapes_round_trip() {
        let mut root = Node::block("");
        root.children
            .as_mut()
            .unwrap()
            .push(leaf("k", "a\"b\\c\nd\te"));
        let dumped = dump(&root);
        assert_eq!(dumped, "\"k\"\t\t\"a\\\"b\\\\c\nd\te\"\n");
        assert_eq!(parse(&dumped).unwrap(), root);
    }

    #[test]
    fn literal_newline_in_a_value_round_trips() {
        let text = "\"Root\"\n{\n\t\"SDL_GamepadBind\"\t\t\"a,b,\nc,d,\"\n}\n";
        assert_eq!(dump(&parse(text).unwrap()), text);
    }

    #[test]
    fn unknown_escape_is_kept_literally() {
        let root = parse("\"k\"\t\t\"C:\\path\"").unwrap();
        assert_eq!(root.find("k").unwrap().value.as_deref(), Some("C:\\path"));
    }

    #[test]
    fn unquoted_tokens() {
        let root = parse("Root\n{\n\tkey value\n}\n").unwrap();
        assert_eq!(
            root.find_path(&["Root", "key"]).unwrap().value.as_deref(),
            Some("value")
        );
    }

    #[test]
    fn comments_are_skipped() {
        let root = parse("// header\n\"Root\"\n{\n\t\"k\"\t\t\"v\" // trailing\n}\n").unwrap();
        assert_eq!(
            root.find_path(&["Root", "k"]).unwrap().value.as_deref(),
            Some("v")
        );
    }

    #[test]
    fn parses_comments_unquoted_tokens_and_escapes() {
        let root = parse("// top\nlibraryfolders\n{\n\t\"0\" { path \"/a b\" } // note\n\t\"1\"\t\"x\\\"y\"\n}\n").unwrap();
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
    }

    #[test]
    fn multiple_top_level_blocks() {
        let root = parse("\"A\"\n{\n}\n\"B\"\n{\n}\n").unwrap();
        let names: Vec<&str> = root.children().map(|n| n.name.as_str()).collect();
        assert_eq!(names, vec!["A", "B"]);
    }

    #[test]
    fn set_path_creates_missing_blocks() {
        let mut root = parse("\"Root\"\n{\n}\n").unwrap();
        root.find_mut("Root")
            .unwrap()
            .set_path(&["a", "b", "c"], "1");
        assert_eq!(
            root.find_path(&["Root", "a", "b", "c"])
                .unwrap()
                .value
                .as_deref(),
            Some("1")
        );
        assert_eq!(
            dump(&root),
            "\"Root\"\n{\n\t\"a\"\n\t{\n\t\t\"b\"\n\t\t{\n\t\t\t\"c\"\t\t\"1\"\n\t\t}\n\t}\n}\n"
        );
    }

    #[test]
    fn set_path_updates_existing_leaf() {
        let mut root = parse("\"Root\"\n{\n\t\"a\"\t\t\"old\"\n}\n").unwrap();
        root.find_mut("Root").unwrap().set_path(&["A"], "new");
        let block = root.find("Root").unwrap();
        assert_eq!(block.children().count(), 1);
        assert_eq!(block.find("a").unwrap().value.as_deref(), Some("new"));
        assert_eq!(block.find("a").unwrap().name, "a");
    }

    #[test]
    fn remove_deletes_every_child_with_the_name() {
        let mut root =
            parse("\"Root\"\n{\n\t\"a\"\t\t\"1\"\n\t\"A\"\t\t\"2\"\n\t\"b\"\t\t\"3\"\n}\n")
                .unwrap();
        let block = root.find_mut("Root").unwrap();
        assert!(block.remove("a"));
        assert!(!block.remove("missing"));
        let names: Vec<&str> = block.children().map(|n| n.name.as_str()).collect();
        assert_eq!(names, vec!["b"]);
        assert!(!leaf("x", "1").remove("x"));
    }

    #[test]
    fn find_path_walks_blocks_only() {
        let root = parse("\"Root\"\n{\n\t\"a\"\t\t\"leaf\"\n\t\"a\"\n\t{\n\t\t\"b\"\t\t\"1\"\n\t}\n\t\"c\"\t\t\"2\"\n}\n").unwrap();
        assert_eq!(
            root.find_path(&["root", "a", "B"])
                .unwrap()
                .value
                .as_deref(),
            Some("1")
        );
        assert!(root.find_path(&["Root", "c", "x"]).is_none());
        assert!(root.find_path(&["Root", "missing"]).is_none());
        assert!(root.find_path(&[]).is_none());
        let mut root = root;
        root.find_path_mut(&["Root", "a", "b"]).unwrap().value = Some("9".into());
        assert_eq!(
            root.find_path(&["Root", "a", "b"])
                .unwrap()
                .value
                .as_deref(),
            Some("9")
        );
        assert!(root.find_path_mut(&["Root", "c", "x"]).is_none());
    }

    #[test]
    fn json_round_trip_keeps_order_and_strings() {
        let root =
            parse("\"Root\"\n{\n\t\"z\"\t\t\"1\"\n\t\"a\"\n\t{\n\t\t\"k\"\t\t\"\"\n\t}\n}\n")
                .unwrap();
        let block = root.find("Root").unwrap();
        let json = block.to_json();
        assert_eq!(json, json!({"z": "1", "a": {"k": ""}}));
        assert_eq!(
            serde_json::to_string(&json).unwrap(),
            "{\"z\":\"1\",\"a\":{\"k\":\"\"}}"
        );
        assert_eq!(&Node::from_json("Root", &json), block);
        assert_eq!(leaf("v", "x").to_json(), json!("x"));
        assert_eq!(Node::from_json("v", &json!("x")), leaf("v", "x"));
    }

    #[test]
    fn localconfig_shape_dump_is_a_fixed_point() {
        let text = "\"UserLocalConfigStore\" { \"Software\" { \"Valve\" { \"Steam\" { \"apps\" { \"620\" { \"LaunchOptions\" \"a \\\"b\\\"\" } } } } } }";
        let root = parse(text).unwrap();
        let dumped = dump(&root);
        assert_eq!(
            root.find_path(&[
                "UserLocalConfigStore",
                "Software",
                "Valve",
                "Steam",
                "apps",
                "620",
                "LaunchOptions"
            ])
            .unwrap()
            .value
            .as_deref(),
            Some("a \"b\"")
        );
        assert!(dumped.contains("\"LaunchOptions\"\t\t\"a \\\"b\\\"\"\n"));
        assert_eq!(parse(&dumped).unwrap(), root);
        assert_eq!(dump(&parse(&dumped).unwrap()), dumped);
    }

    #[test]
    fn syntax_errors() {
        for text in [
            "\"unterminated",
            "\"Root\"\n{\n",
            "}",
            "\"key\"",
            "\"Root\"\n{\n\t\"key\"\n}\n",
            "{",
        ] {
            assert!(parse(text).is_err(), "{text:?} should not parse");
        }
        assert_eq!(
            parse("\"Root\"\n{\n\t\"key\"\n}\n").unwrap_err(),
            "key \"key\" has no value"
        );
        assert_eq!(parse("\"a\nb").unwrap_err(), "unterminated string (line 2)");
    }
}
