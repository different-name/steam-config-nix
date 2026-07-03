import pytest

from steam_config_patcher.formats.keyvalues import prepare_keyvalues
from steam_config_patcher.types import ConfigPatch, Deletion
from steam_config_patcher.vdf import text

CONFIG_VDF = """\
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

STEAM_PATH = ("InstallConfigStore", "Software", "Valve", "Steam")
MAPPING_PATH = STEAM_PATH + ("CompatToolMapping",)


def write_config(tmp_path):
    path = tmp_path / "config.vdf"
    path.write_text(CONFIG_VDF, encoding="utf-8")
    return path


def parse(path):
    return text.loads(path.read_text(encoding="utf-8"))


def make_patch(file_path, data, deletions=()):
    return ConfigPatch(
        file_path=file_path,
        file_format="keyvalues",
        data=data,
        deletions=list(deletions),
    )


def apply(patch):
    data = prepare_keyvalues(patch)
    if data is None:
        return False
    patch.file_path.write_bytes(data)
    return True


def find_value(kv, key_path):
    values = [node.value for node in kv.find_all(*key_path)]
    assert len(values) == 1, f"expected exactly one value at {key_path}"
    return values[0]


def nest(key_path, value):
    for key in reversed(key_path):
        value = {key: value}
    return value


def test_updates_existing_leaf(tmp_path):
    path = write_config(tmp_path)
    patch = make_patch(path, nest(MAPPING_PATH + ("0", "name"), "GE-Proton"))

    assert apply(patch)

    kv = parse(path)
    assert find_value(kv, MAPPING_PATH + ("0", "name")) == "GE-Proton"
    assert find_value(kv, MAPPING_PATH + ("0", "priority")) == "75"


def test_creates_missing_nested_path(tmp_path):
    path = write_config(tmp_path)
    new_app = {"config": "", "name": "GE-Proton", "priority": "250"}
    patch = make_patch(path, nest(MAPPING_PATH + ("1091500",), new_app))

    assert apply(patch)

    kv = parse(path)
    for key, value in new_app.items():
        assert find_value(kv, MAPPING_PATH + ("1091500", key)) == value
    assert find_value(kv, MAPPING_PATH + ("0", "name")) == "proton_experimental"


def test_int_values_are_written_as_strings(tmp_path):
    path = write_config(tmp_path)
    patch = make_patch(path, nest(MAPPING_PATH + ("0", "priority"), 250))

    assert apply(patch)

    assert find_value(parse(path), MAPPING_PATH + ("0", "priority")) == "250"


def test_unchanged_data_prepares_nothing(tmp_path):
    path = write_config(tmp_path)
    patch = make_patch(path, nest(MAPPING_PATH + ("0", "name"), "proton_experimental"))

    assert prepare_keyvalues(patch) is None

    assert path.read_text(encoding="utf-8") == CONFIG_VDF


def test_missing_file_is_skipped(tmp_path):
    path = tmp_path / "config.vdf"
    patch = make_patch(path, nest(MAPPING_PATH + ("0", "name"), "GE-Proton"))

    assert prepare_keyvalues(patch) is None

    assert not path.exists()


def test_prepare_does_not_write(tmp_path):
    path = write_config(tmp_path)
    patch = make_patch(path, nest(MAPPING_PATH + ("0", "name"), "GE-Proton"))

    assert prepare_keyvalues(patch) is not None

    assert path.read_text(encoding="utf-8") == CONFIG_VDF


def test_refuses_to_overwrite_block_with_leaf(tmp_path):
    path = write_config(tmp_path)
    patch = make_patch(path, nest(MAPPING_PATH + ("0",), "not-a-block"))

    with pytest.raises(ValueError):
        prepare_keyvalues(patch)

    assert path.read_text(encoding="utf-8") == CONFIG_VDF


def test_duplicate_blocks_are_all_updated(tmp_path):
    path = tmp_path / "config.vdf"
    path.write_text(
        """\
"Root"
{
	"Apps"
	{
		"620"
		{
			"LaunchOptions"		"a"
		}
	}
	"Apps"
	{
		"620"
		{
			"LaunchOptions"		"b"
		}
	}
}
""",
        encoding="utf-8",
    )
    patch = make_patch(path, nest(("Root", "Apps", "620", "LaunchOptions"), "c"))

    assert apply(patch)

    values = [n.value for n in parse(path).find_all("Root", "Apps", "620", "LaunchOptions")]
    assert values == ["c", "c"]


def test_deletion_with_matching_guard(tmp_path):
    path = write_config(tmp_path)
    patch = make_patch(
        path,
        {},
        deletions=[
            Deletion(
                key_path=MAPPING_PATH + ("0",),
                guard_path=("name",),
                expected="proton_experimental",
            )
        ],
    )

    assert apply(patch)

    assert list(parse(path).find_all(*MAPPING_PATH, "0")) == []


def test_deletion_with_mismatched_guard_keeps_key(tmp_path):
    path = write_config(tmp_path)
    patch = make_patch(
        path,
        {},
        deletions=[
            Deletion(
                key_path=MAPPING_PATH + ("0",),
                guard_path=("name",),
                expected="GE-Proton",
            )
        ],
    )

    assert prepare_keyvalues(patch) is None

    assert path.read_text(encoding="utf-8") == CONFIG_VDF


def test_deletion_guarded_by_leaf_value(tmp_path):
    path = write_config(tmp_path)
    patch = make_patch(
        path,
        {},
        deletions=[
            Deletion(
                key_path=STEAM_PATH + ("AutoUpdateWindowEnabled",),
                expected="0",
            )
        ],
    )

    assert apply(patch)

    assert list(parse(path).find_all(*STEAM_PATH, "AutoUpdateWindowEnabled")) == []


def test_deletion_of_missing_key_is_noop(tmp_path):
    path = write_config(tmp_path)
    patch = make_patch(
        path,
        {},
        deletions=[Deletion(key_path=MAPPING_PATH + ("999",))],
    )

    assert prepare_keyvalues(patch) is None

    assert path.read_text(encoding="utf-8") == CONFIG_VDF
