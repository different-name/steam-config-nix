use std::path::Path;

pub enum Refused {
    ParentMissing(String),
    Create(String),
}

impl Refused {
    pub fn log_line(&self) -> String {
        match self {
            Refused::ParentMissing(parent) => {
                format!("prefixPath parent {parent} does not exist, refusing to create it")
            }
            Refused::Create(err) => err.clone(),
        }
    }

    pub fn notification(&self) -> String {
        match self {
            Refused::ParentMissing(parent) => {
                format!("prefixPath parent {parent} is missing, is the drive mounted?")
            }
            Refused::Create(err) => err.clone(),
        }
    }
}

pub fn parent_of(path: &Path) -> &Path {
    path.parent().unwrap_or(Path::new("/"))
}

pub fn prepare(path: &Path) -> Result<(), Refused> {
    let parent = parent_of(path);
    if !parent.is_dir() {
        return Err(Refused::ParentMissing(parent.display().to_string()));
    }
    std::fs::create_dir_all(path).map_err(|e| Refused::Create(format!("{}: {e}", path.display())))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::launch::spec::tests::temp;

    #[test]
    fn prepare_cases() {
        let root = temp("prefix");
        assert!(
            prepare(&root.join("pfxs/620")).is_err_and(|e| matches!(e, Refused::ParentMissing(_)))
        );
        assert!(!root.join("pfxs").exists());
        prepare(&root.join("620")).ok().unwrap();
        assert!(root.join("620").is_dir());
        prepare(&root.join("620")).ok().unwrap();
        std::fs::write(root.join("file"), "").unwrap();
        assert!(prepare(&root.join("file")).is_err_and(|e| matches!(e, Refused::Create(_))));
        let _ = std::fs::remove_dir_all(&root);
    }
}
