use std::fs;
use std::path::Path;

use steam_config_vdf::text::parse;

pub fn tool_name(dir: &Path) -> Result<String, String> {
    let vdf = dir.join("compatibilitytool.vdf");
    let text = fs::read_to_string(&vdf).map_err(|e| format!("{}: {e}", vdf.display()))?;
    let root = parse(&text).map_err(|e| format!("{}: {e}", vdf.display()))?;
    root.find("compatibilitytools")
        .and_then(|t| t.find("compat_tools"))
        .and_then(|tools| tools.children().find(|c| c.children.is_some()))
        .map(|tool| tool.name.clone())
        .ok_or_else(|| format!("{}: no compat tool declared", vdf.display()))
}

#[cfg(test)]
mod tests {
    use super::tool_name;
    use std::fs;
    use std::path::PathBuf;

    const COMPAT_TOOL_VDF: &str = "\"compatibilitytools\"\n{\n\t\"compat_tools\"\n\t{\n\t\t\"GE-Proton\"\n\t\t{\n\t\t\t\"install_path\"\t\t\".\"\n\t\t\t\"display_name\"\t\t\"GE-Proton (latest)\"\n\t\t\t\"from_oslist\"\t\t\"windows\"\n\t\t\t\"to_oslist\"\t\t\"linux\"\n\t\t}\n\t}\n}\n";

    fn tool_dir(name: &str, content: Option<&str>) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("scn-compat-{}-{name}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        if let Some(content) = content {
            fs::write(dir.join("compatibilitytool.vdf"), content).unwrap();
        }
        dir
    }

    #[test]
    fn resolves_internal_name() {
        let dir = tool_dir("a", Some(COMPAT_TOOL_VDF));
        assert_eq!(tool_name(&dir).unwrap(), "GE-Proton");
    }

    #[test]
    fn first_tool_wins_when_multiple_declared() {
        let content = "\"compatibilitytools\"\n{\n\t\"compat_tools\"\n\t{\n\t\t\"First-Tool\"\n\t\t{\n\t\t\t\"install_path\"\t\t\".\"\n\t\t}\n\t\t\"Second-Tool\"\n\t\t{\n\t\t\t\"install_path\"\t\t\".\"\n\t\t}\n\t}\n}\n";
        let dir = tool_dir("b", Some(content));
        assert_eq!(tool_name(&dir).unwrap(), "First-Tool");
    }

    #[test]
    fn missing_vdf_is_an_error() {
        let dir = tool_dir("c", None);
        assert!(tool_name(&dir).is_err());
    }

    #[test]
    fn vdf_without_tools_is_an_error() {
        let dir = tool_dir(
            "d",
            Some("\"compatibilitytools\"\n{\n\t\"compat_tools\"\n\t{\n\t}\n}\n"),
        );
        assert!(tool_name(&dir).unwrap_err().contains("no compat tool"));
    }
}
