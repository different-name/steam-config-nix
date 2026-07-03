import pytest

from steam_config_patcher.vdf.text import VdfNode, VdfSyntaxError, dumps, loads

SAMPLE = """\
"InstallConfigStore"
{
	"Software"
	{
		"Valve"
		{
			"Steam"
			{
				"CompatToolMapping"
				{
					"0"
					{
						"name"		"proton_experimental"
						"config"		""
						"priority"		"75"
					}
				}
				"AutoUpdateWindowEnabled"		"0"
			}
		}
	}
}
"""


def test_parses_nested_blocks_and_leaves():
    root = loads(SAMPLE)

    path = (
        "InstallConfigStore",
        "Software",
        "Valve",
        "Steam",
        "CompatToolMapping",
        "0",
        "name",
    )
    assert [n.value for n in root.find_all(*path)] == ["proton_experimental"]


def test_dumps_matches_steam_style():
    assert dumps(loads(SAMPLE)) == SAMPLE


def test_round_trip_is_stable():
    root = loads(SAMPLE)

    assert loads(dumps(root)) == root


def test_duplicate_keys_and_order_are_preserved():
    text = '"Root"\n{\n\t"A"\t\t"1"\n\t"A"\t\t"2"\n\t"B"\t\t"3"\n}\n'

    root = loads(text)

    assert [(n.name, n.value) for n in root.find("Root").children] == [
        ("A", "1"),
        ("A", "2"),
        ("B", "3"),
    ]
    assert dumps(root) == text


def test_find_all_is_case_insensitive():
    root = loads('"Root"\n{\n\t"Apps"\t\t"x"\n}\n')

    assert [n.value for n in root.find_all("root", "APPS")] == ["x"]


def test_case_is_preserved_on_write():
    text = '"RoOt"\n{\n\t"ApPs"\t\t"x"\n}\n'

    assert dumps(loads(text)) == text


def test_escapes_round_trip():
    root = VdfNode(children=[VdfNode("k", value='a"b\\c\nd\te')])

    dumped = dumps(root)

    assert dumped == '"k"\t\t"a\\"b\\\\c\\nd\\te"\n'
    assert loads(dumped) == root


def test_unknown_escape_is_kept_literally():
    root = loads('"k"\t\t"C:\\path"')

    assert root.find("k").value == "C:\\path"


def test_unquoted_tokens():
    root = loads("Root\n{\n\tkey value\n}\n")

    assert root.find_all("Root", "key").__next__().value == "value"


def test_comments_are_skipped():
    root = loads('// header\n"Root"\n{\n\t"k"\t\t"v" // trailing\n}\n')

    assert next(root.find_all("Root", "k")).value == "v"


def test_multiple_top_level_blocks():
    root = loads('"A"\n{\n}\n"B"\n{\n}\n')

    assert [n.name for n in root.children] == ["A", "B"]


def test_set_path_creates_missing_blocks():
    root = loads('"Root"\n{\n}\n')

    root.find("Root").set_path(("a", "b", "c"), "1")

    assert next(root.find_all("Root", "a", "b", "c")).value == "1"


def test_set_path_updates_existing_leaf():
    root = loads('"Root"\n{\n\t"a"\t\t"old"\n}\n')

    root.find("Root").set_path(("a",), "new")

    assert [n.value for n in root.find_all("Root", "a")] == ["new"]


def test_remove_deletes_child():
    root = loads('"Root"\n{\n\t"a"\t\t"1"\n\t"b"\t\t"2"\n}\n')

    assert root.find("Root").remove("a")
    assert not root.find("Root").remove("missing")

    assert [n.name for n in root.find("Root").children] == ["b"]


@pytest.mark.parametrize(
    "text",
    [
        '"unterminated',
        '"Root"\n{\n',
        "}",
        '"key"',
        '"Root"\n{\n\t"key"\n}\n',
        "{",
    ],
)
def test_syntax_errors(text):
    with pytest.raises(VdfSyntaxError):
        loads(text)


def test_syntax_error_reports_line():
    with pytest.raises(VdfSyntaxError) as excinfo:
        loads('"Root"\n{\n\t"key"\n}\n')

    assert excinfo.value.line == 4
