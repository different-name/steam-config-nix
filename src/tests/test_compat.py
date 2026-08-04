import pytest

from steam_config_patcher.compat import resolve_compat_tool_name

COMPAT_TOOL_VDF = """\
"compatibilitytools"
{
	"compat_tools"
	{
		"GE-Proton"
		{
			"install_path"		"."
			"display_name"		"GE-Proton (latest)"
			"from_oslist"		"windows"
			"to_oslist"		"linux"
		}
	}
}
"""


def make_tool_dir(tmp_path, content=COMPAT_TOOL_VDF):
    tool_dir = tmp_path / "tool"
    tool_dir.mkdir()
    (tool_dir / "compatibilitytool.vdf").write_text(content, encoding="utf-8")
    return tool_dir


def test_resolves_internal_name(tmp_path):
    tool_dir = make_tool_dir(tmp_path)

    assert resolve_compat_tool_name(tool_dir) == "GE-Proton"


def test_first_tool_wins_when_multiple_declared(tmp_path):
    content = (
        '"compatibilitytools"\n{\n\t"compat_tools"\n\t{\n'
        '\t\t"First-Tool"\n\t\t{\n\t\t\t"install_path"\t\t"."\n\t\t}\n'
        '\t\t"Second-Tool"\n\t\t{\n\t\t\t"install_path"\t\t"."\n\t\t}\n'
        "\t}\n}\n"
    )
    tool_dir = make_tool_dir(tmp_path, content)

    assert resolve_compat_tool_name(tool_dir) == "First-Tool"


def test_missing_vdf_raises(tmp_path):
    tool_dir = tmp_path / "tool"
    tool_dir.mkdir()

    with pytest.raises(FileNotFoundError):
        resolve_compat_tool_name(tool_dir)


def test_vdf_without_tools_raises(tmp_path):
    tool_dir = make_tool_dir(tmp_path, '"compatibilitytools"\n{\n\t"compat_tools"\n\t{\n\t}\n}\n')

    with pytest.raises(ValueError):
        resolve_compat_tool_name(tool_dir)
