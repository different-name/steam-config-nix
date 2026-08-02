from pathlib import Path

from steam_config_patcher.vdf import text


def find_compatibilitytool_vdf(tool_dir: Path) -> Path:
    """Return the path to compatibilitytool.vdf within a tool package.

    Accepts both the nixpkgs layout (VDF at the tool root / steamcompattool
    output) and layouts that nest it under ``bin/`` (e.g. chaotic's
    proton-cachyos).
    """
    candidates = (
        tool_dir / "compatibilitytool.vdf",
        tool_dir / "bin" / "compatibilitytool.vdf",
    )
    for vdf_path in candidates:
        if vdf_path.is_file():
            return vdf_path
    raise FileNotFoundError(
        f"no compatibilitytool.vdf found in {tool_dir} or {tool_dir / 'bin'}"
    )


def resolve_compat_tool_name(tool_dir: Path) -> str:
    vdf_path = find_compatibilitytool_vdf(tool_dir)

    root = text.loads(vdf_path.read_text(encoding="utf-8"))
    for tools in root.find_all("compatibilitytools", "compat_tools"):
        for tool in tools.children or []:
            if tool.is_block:
                return tool.name

    raise ValueError(f"no compat tool declared in {vdf_path}")
