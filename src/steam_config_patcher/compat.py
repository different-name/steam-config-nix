from pathlib import Path

from steam_config_patcher.vdf import text


def resolve_compat_tool_name(tool_dir: Path) -> str:
    vdf_paths = [
        tool_dir / "compatibilitytool.vdf",
        tool_dir / "bin" / "compatibilitytool.vdf",
    ]

    for vdf_path in vdf_paths:
        if vdf_path.is_file():
            break
    else:
        raise FileNotFoundError(f"no compatibilitytool.vdf found in {tool_dir}")

    root = text.loads(vdf_path.read_text(encoding="utf-8"))
    for tools in root.find_all("compatibilitytools", "compat_tools"):
        for tool in tools.children or []:
            if tool.is_block:
                return tool.name

    raise ValueError(f"no compat tool declared in {vdf_path}")
