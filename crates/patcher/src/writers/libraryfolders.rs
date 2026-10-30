use std::fs;
use std::path::Path;

use steam_config_vdf::text::Node;

use crate::log;
use crate::record::Record;
use crate::state::State;
use crate::writers::{Delta, Outcome, read_tree, text_outcome};

fn folder_path(block: &Node) -> Option<&str> {
    block
        .find("path")
        .filter(|p| p.children.is_none())
        .and_then(|p| p.value.as_deref())
}

pub fn prepare(
    state: &State,
    steam_dir: &Path,
    record: &Record,
) -> Result<Option<Outcome>, String> {
    let path = steam_dir.join("config/libraryfolders.vdf");
    let Some((original, mut tree)) = read_tree(&path)? else {
        log("libraryfolders.vdf is missing");
        return Ok(None);
    };
    let Some(folders) = tree
        .find_mut("libraryfolders")
        .filter(|n| n.children.is_some())
    else {
        return Err("libraryfolders.vdf has no libraryfolders block".into());
    };
    let mut next_index = folders
        .children()
        .filter_map(|c| c.name.parse::<i64>().ok())
        .max()
        .unwrap_or(-1)
        + 1;
    let mut recorded: Vec<String> = Vec::new();
    for configured in &state.library_folders {
        let present = folders
            .children()
            .any(|c| c.children.is_some() && folder_path(c) == Some(configured));
        if present {
            if record.library_folders.contains(configured) {
                recorded.push(configured.clone());
            }
            continue;
        }
        if let Err(e) = fs::create_dir_all(configured) {
            return Err(format!(
                "library folder {configured} could not be created: {e}"
            ));
        }
        let mut block = Node::block(&next_index.to_string());
        block.set_path(&["path"], configured);
        block.set_path(&["label"], "");
        folders.children.as_mut().unwrap().push(block);
        next_index += 1;
        recorded.push(configured.clone());
    }
    let removed: Vec<&String> = record
        .library_folders
        .iter()
        .filter(|p| !state.library_folders.contains(p))
        .collect();
    folders.children.as_mut().unwrap().retain(|c| {
        !(c.children.is_some() && folder_path(c).is_some_and(|p| removed.iter().any(|r| *r == p)))
    });
    Ok(Some(text_outcome(
        "libraryfolders.vdf",
        &path,
        &original,
        &tree,
        Delta::LibraryFolders(recorded),
    )))
}

#[cfg(test)]
mod tests {
    use super::prepare;
    use crate::record::Record;
    use crate::writers::testing::{state, temp, write};
    use std::fs;
    use std::path::PathBuf;
    use steam_config_vdf::text::parse;

    fn folders(steam: &PathBuf) -> Vec<(String, Option<String>, Option<String>)> {
        let text = fs::read_to_string(steam.join("config/libraryfolders.vdf")).unwrap();
        let root = parse(&text).unwrap();
        root.find("libraryfolders")
            .unwrap()
            .children()
            .map(|c| {
                (
                    c.name.clone(),
                    c.find("path").and_then(|p| p.value.clone()),
                    c.find("label").and_then(|p| p.value.clone()),
                )
            })
            .collect()
    }

    fn apply(steam: &PathBuf, extra: &str, record: &mut Record) -> bool {
        let outcome = prepare(&state(extra), steam, record).unwrap().unwrap();
        let wrote = outcome.bytes.is_some();
        if let Some(bytes) = &outcome.bytes {
            fs::write(&outcome.path, bytes).unwrap();
        }
        record.apply(outcome.delta);
        wrote
    }

    fn seed(steam: &PathBuf) {
        write(
            &steam.join("config/libraryfolders.vdf"),
            &format!(
                "\"libraryfolders\"\n{{\n\t\"0\"\n\t{{\n\t\t\"path\"\t\t\"{}\"\n\t\t\"label\"\t\t\"\"\n\t\t\"contentid\"\t\t\"1\"\n\t}}\n}}\n",
                steam.display()
            ),
        );
    }

    #[test]
    fn adds_a_block_creates_the_dir_and_removes_it_later() {
        let steam = temp("libraryfolders");
        seed(&steam);
        let lib = steam.join("lib2");
        let extra = format!(r#""libraryFolders": ["{}"]"#, lib.display());
        let mut record = Record::default();
        assert!(apply(&steam, &extra, &mut record));
        assert!(lib.is_dir());
        let f = folders(&steam);
        assert_eq!(f.len(), 2);
        assert_eq!(
            f[1],
            (
                "1".into(),
                Some(lib.display().to_string()),
                Some(String::new())
            )
        );
        assert_eq!(record.library_folders, vec![lib.display().to_string()]);
        assert!(!apply(&steam, &extra, &mut record));
        assert_eq!(record.library_folders, vec![lib.display().to_string()]);
        assert!(apply(&steam, "", &mut record));
        assert_eq!(folders(&steam).len(), 1);
        assert!(record.library_folders.is_empty());
        assert!(lib.is_dir());
    }

    #[test]
    fn a_folder_steam_already_has_is_not_recorded_or_removed() {
        let steam = temp("libraryfolders-existing");
        seed(&steam);
        let extra = format!(r#""libraryFolders": ["{}"]"#, steam.display());
        let mut record = Record::default();
        assert!(!apply(&steam, &extra, &mut record));
        assert!(record.library_folders.is_empty());
        assert!(!apply(&steam, "", &mut record));
        assert_eq!(folders(&steam).len(), 1);
    }

    #[test]
    fn a_folder_that_cannot_be_created_fails_the_file() {
        let steam = temp("libraryfolders-blocked");
        seed(&steam);
        fs::write(steam.join("blocker"), b"").unwrap();
        let lib = steam.join("blocker/lib");
        let extra = format!(r#""libraryFolders": ["{}"]"#, lib.display());
        let Err(err) = prepare(&state(&extra), &steam, &Record::default()) else {
            panic!("expected an error");
        };
        assert!(err.contains("could not be created"));
        assert_eq!(folders(&steam).len(), 1);
    }

    #[test]
    fn missing_file_is_skipped() {
        let steam = temp("libraryfolders-missing");
        assert!(
            prepare(&state(""), &steam, &Record::default())
                .unwrap()
                .is_none()
        );
    }
}
