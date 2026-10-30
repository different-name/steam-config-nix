use serde_json::Value;
use steam_config_vdf::text::Node;

use crate::record::KeyEntry;

pub struct Managed<'a> {
    file: &'a str,
    prev: &'a [KeyEntry],
    entries: Vec<KeyEntry>,
}

fn ensure_block<'n>(tree: &'n mut Node, path: &[&str]) -> &'n mut Node {
    let mut node = tree;
    for name in path {
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
    node
}

fn parent_mut<'n>(tree: &'n mut Node, path: &[String]) -> Option<&'n mut Node> {
    let (_, blocks) = path.split_last()?;
    let mut node = tree;
    for name in blocks {
        node = node
            .children
            .as_mut()?
            .iter_mut()
            .find(|c| c.name.eq_ignore_ascii_case(name) && c.children.is_some())?;
    }
    Some(node)
}

fn strs(path: &[String]) -> Vec<&str> {
    path.iter().map(String::as_str).collect()
}

fn current_value(node: Option<&Node>, guard: &[String]) -> Option<String> {
    let node = node?;
    let target = if guard.is_empty() {
        node
    } else {
        node.find_path(&strs(guard))?
    };
    if target.children.is_some() {
        return None;
    }
    Some(target.value.clone().unwrap_or_default())
}

impl<'a> Managed<'a> {
    pub fn new(file: &'a str, prev: &'a [KeyEntry]) -> Self {
        Managed {
            file,
            prev,
            entries: Vec::new(),
        }
    }

    fn prior(&self, tree: &Node, path: &[&str]) -> Value {
        if let Some(entry) = self
            .prev
            .iter()
            .find(|e| e.file == self.file && e.path == path)
        {
            return entry.prior.clone();
        }
        match tree.find_path(path) {
            Some(node) => node.to_json(),
            None => Value::Null,
        }
    }

    fn push(&mut self, tree: &Node, path: &[&str], guard: &[&str], ours: &str) {
        let prior = self.prior(tree, path);
        self.entries.push(KeyEntry {
            file: self.file.to_string(),
            path: path.iter().map(|s| s.to_string()).collect(),
            guard: guard.iter().map(|s| s.to_string()).collect(),
            ours: ours.to_string(),
            prior,
        });
    }

    pub fn set_leaf(&mut self, tree: &mut Node, path: &[&str], value: &str) {
        self.push(tree, path, &[], value);
        tree.set_path(path, value);
    }

    pub fn set_block(
        &mut self,
        tree: &mut Node,
        path: &[&str],
        guard: &str,
        leaves: &[(&str, &str)],
    ) {
        let ours = leaves
            .iter()
            .find(|(k, _)| k.eq_ignore_ascii_case(guard))
            .map(|(_, v)| *v)
            .unwrap_or_default();
        self.push(tree, path, &[guard], ours);
        let block = ensure_block(tree, path);
        for (key, value) in leaves {
            block.set_path(&[key], value);
        }
    }

    pub fn revert(&mut self, tree: &mut Node) {
        for entry in self.prev.iter().filter(|e| e.file == self.file) {
            if self.entries.iter().any(|e| e.path == entry.path) {
                continue;
            }
            let Some(parent) = parent_mut(tree, &entry.path) else {
                continue;
            };
            let leaf = entry.path.last().unwrap();
            let Some(index) = parent
                .children
                .as_ref()
                .and_then(|c| c.iter().position(|n| n.name.eq_ignore_ascii_case(leaf)))
            else {
                continue;
            };
            let children = parent.children.as_mut().unwrap();
            if current_value(Some(&children[index]), &entry.guard).as_deref()
                != Some(entry.ours.as_str())
            {
                continue;
            }
            match &entry.prior {
                Value::Null => {
                    children.remove(index);
                }
                prior => {
                    let name = children[index].name.clone();
                    children[index] = Node::from_json(&name, prior);
                }
            }
        }
    }

    pub fn finish(self) -> Vec<KeyEntry> {
        self.entries
    }
}

#[cfg(test)]
mod tests {
    use super::Managed;
    use crate::record::KeyEntry;
    use serde_json::{Value, json};
    use steam_config_vdf::text::{dump, parse};

    const CONFIG: &str = "\"InstallConfigStore\"\n{\n\t\"Accessibility\"\n\t{\n\t\t\"DesktopUIScale\"\t\t\"1\"\n\t}\n\t\"Software\"\n\t{\n\t\t\"Valve\"\n\t\t{\n\t\t\t\"Steam\"\n\t\t\t{\n\t\t\t\t\"CompatToolMapping\"\n\t\t\t\t{\n\t\t\t\t\t\"620\"\n\t\t\t\t\t{\n\t\t\t\t\t\t\"config\"\t\t\"\"\n\t\t\t\t\t\t\"name\"\t\t\"user_tool\"\n\t\t\t\t\t\t\"priority\"\t\t\"250\"\n\t\t\t\t\t}\n\t\t\t\t}\n\t\t\t}\n\t\t}\n\t}\n}\n";
    const SCALE: [&str; 3] = ["InstallConfigStore", "Accessibility", "DesktopUIScale"];
    const MAPPING: [&str; 5] = [
        "InstallConfigStore",
        "Software",
        "Valve",
        "Steam",
        "CompatToolMapping",
    ];

    fn mapping(id: &str) -> Vec<&str> {
        let mut p = MAPPING.to_vec();
        p.push(id);
        p
    }

    fn value(text: &str, path: &[&str]) -> Option<String> {
        parse(text)
            .unwrap()
            .find_path(path)
            .and_then(|n| n.value.clone())
    }

    #[test]
    fn first_write_records_the_prior_value() {
        let mut tree = parse(CONFIG).unwrap();
        let mut m = Managed::new("config", &[]);
        m.set_leaf(&mut tree, &SCALE, "1.25");
        m.set_block(
            &mut tree,
            &mapping("620"),
            "name",
            &[("config", ""), ("name", "tool"), ("priority", "250")],
        );
        m.set_block(
            &mut tree,
            &mapping("0"),
            "name",
            &[("config", ""), ("name", "GE"), ("priority", "75")],
        );
        m.set_leaf(&mut tree, &["InstallConfigStore", "New", "Leaf"], "x");
        let entries = m.finish();
        assert_eq!(entries[0].prior, json!("1"));
        assert_eq!(entries[0].ours, "1.25");
        assert_eq!(
            entries[1].prior,
            json!({"config": "", "name": "user_tool", "priority": "250"})
        );
        assert_eq!(entries[1].ours, "tool");
        assert_eq!(entries[1].guard, vec!["name"]);
        assert_eq!(entries[2].prior, Value::Null);
        assert_eq!(entries[3].prior, Value::Null);
        let text = dump(&tree);
        assert_eq!(value(&text, &SCALE).as_deref(), Some("1.25"));
        assert_eq!(
            value(&text, &[&mapping("620")[..], &["name"]].concat()).as_deref(),
            Some("tool")
        );
        assert_eq!(
            value(&text, &[&mapping("0")[..], &["priority"]].concat()).as_deref(),
            Some("75")
        );
        assert_eq!(
            value(&text, &["InstallConfigStore", "New", "Leaf"]).as_deref(),
            Some("x")
        );
    }

    #[test]
    fn a_later_write_keeps_the_original_prior() {
        let mut tree = parse(CONFIG).unwrap();
        let mut m = Managed::new("config", &[]);
        m.set_leaf(&mut tree, &SCALE, "1.25");
        let first = m.finish();
        let mut m = Managed::new("config", &first);
        m.set_leaf(&mut tree, &SCALE, "1.5");
        let second = m.finish();
        assert_eq!(second[0].prior, json!("1"));
        assert_eq!(second[0].ours, "1.5");
    }

    #[test]
    fn set_block_matches_the_guard_case_insensitively() {
        let mut tree = parse(CONFIG).unwrap();
        let mut m = Managed::new("config", &[]);
        m.set_block(&mut tree, &mapping("1"), "Name", &[("name", "t")]);
        assert_eq!(m.finish()[0].ours, "t");
    }

    #[test]
    fn revert_restores_prior_values_and_deletes_absent_ones() {
        let mut tree = parse(CONFIG).unwrap();
        let mut m = Managed::new("config", &[]);
        m.set_leaf(&mut tree, &SCALE, "1.25");
        m.set_block(
            &mut tree,
            &mapping("620"),
            "name",
            &[("config", ""), ("name", "tool"), ("priority", "250")],
        );
        m.set_block(
            &mut tree,
            &mapping("0"),
            "name",
            &[("config", ""), ("name", "GE"), ("priority", "75")],
        );
        let prev = m.finish();
        let mut m = Managed::new("config", &prev);
        m.revert(&mut tree);
        assert!(m.finish().is_empty());
        assert_eq!(dump(&tree), CONFIG);
    }

    #[test]
    fn revert_skips_paths_still_desired() {
        let mut tree = parse(CONFIG).unwrap();
        let mut m = Managed::new("config", &[]);
        m.set_leaf(&mut tree, &SCALE, "1.25");
        let prev = m.finish();
        let mut m = Managed::new("config", &prev);
        m.set_leaf(&mut tree, &SCALE, "1.5");
        m.revert(&mut tree);
        assert_eq!(value(&dump(&tree), &SCALE).as_deref(), Some("1.5"));
        assert_eq!(m.finish().len(), 1);
    }

    #[test]
    fn revert_leaves_a_value_the_user_changed() {
        let mut tree = parse(CONFIG).unwrap();
        let mut m = Managed::new("config", &[]);
        m.set_leaf(&mut tree, &SCALE, "1.25");
        m.set_block(&mut tree, &mapping("620"), "name", &[("name", "tool")]);
        let prev = m.finish();
        tree.find_path_mut(&SCALE).unwrap().value = Some("2".into());
        tree.find_path_mut(&[&mapping("620")[..], &["name"]].concat())
            .unwrap()
            .value = Some("other".into());
        let mut m = Managed::new("config", &prev);
        m.revert(&mut tree);
        assert!(m.finish().is_empty());
        let text = dump(&tree);
        assert_eq!(value(&text, &SCALE).as_deref(), Some("2"));
        assert_eq!(
            value(&text, &[&mapping("620")[..], &["name"]].concat()).as_deref(),
            Some("other")
        );
    }

    #[test]
    fn revert_ignores_missing_nodes_and_other_files() {
        let mut tree = parse(CONFIG).unwrap();
        let prev = vec![
            KeyEntry {
                file: "config".into(),
                path: vec!["InstallConfigStore".into(), "Gone".into()],
                guard: vec![],
                ours: "1".into(),
                prior: json!("0"),
            },
            KeyEntry {
                file: "other".into(),
                path: SCALE.iter().map(|s| s.to_string()).collect(),
                guard: vec![],
                ours: "1".into(),
                prior: Value::Null,
            },
        ];
        let mut m = Managed::new("config", &prev);
        m.revert(&mut tree);
        assert_eq!(dump(&tree), CONFIG);
    }
}
