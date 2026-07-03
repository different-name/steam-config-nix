import struct
from io import BytesIO

import pytest
import vdf

from steam_config_patcher.formats.binary_keyvalues import (
    delete_key,
    patch_binary_keyvalues,
    recursive_update,
)
from steam_config_patcher.types import ConfigPatch, Deletion


def _vdf_handles_uint32():
    try:
        vdf.binary_dump({"s": {"appid": 0x914B9DA1}}, BytesIO())
    except struct.error:
        return False
    return True


requires_patched_vdf = pytest.mark.skipif(
    not _vdf_handles_uint32(),
    reason="needs the uint32-patched vdf package (applied in the nix build)",
)


def shortcut(appid, name):
    return {
        "appid": appid,
        "AppName": name,
        "Exe": '"/path/to/game"',
        "StartDir": '"/path/to"',
        "icon": "",
        "LaunchOptions": "",
        "IsHidden": 0,
        "AllowDesktopConfig": 1,
        "OpenVR": 0,
        "tags": {},
    }


def write_shortcuts(path, data):
    with path.open("wb") as f:
        vdf.binary_dump(data, f)


def read_shortcuts(path):
    with path.open("rb") as f:
        return vdf.binary_load(f)


def make_patch(file_path, data, deletions=(), close_steam=False):
    return ConfigPatch(
        file_path=file_path,
        file_format="binary-keyvalues",
        data=data,
        close_steam=close_steam,
        deletions=list(deletions),
    )


def test_recursive_update_adds_missing_keys():
    destination = {"shortcuts": {}}

    assert recursive_update(destination, {"shortcuts": {"0": {"appid": 1}}})

    assert destination == {"shortcuts": {"0": {"appid": 1}}}


def test_recursive_update_changes_leaf():
    destination = {"shortcuts": {"0": {"appid": 1, "AppName": "Old"}}}

    assert recursive_update(destination, {"shortcuts": {"0": {"AppName": "New"}}})

    assert destination == {"shortcuts": {"0": {"appid": 1, "AppName": "New"}}}


def test_recursive_update_identical_reports_unmodified():
    destination = {"shortcuts": {"0": {"appid": 1}}}

    assert not recursive_update(destination, {"shortcuts": {"0": {"appid": 1}}})

    assert destination == {"shortcuts": {"0": {"appid": 1}}}


def test_delete_key_removes_nested_entry():
    destination = {"shortcuts": {"0": {"appid": 1}, "1": {"appid": 2}}}

    assert delete_key(destination, Deletion(key_path=("shortcuts", "0")))

    assert destination == {"shortcuts": {"1": {"appid": 2}}}


def test_delete_key_missing_path_reports_unmodified():
    destination = {"shortcuts": {}}

    assert not delete_key(destination, Deletion(key_path=("shortcuts", "0")))


def test_adds_new_shortcut(fake_steam, tmp_path):
    path = tmp_path / "shortcuts.vdf"
    write_shortcuts(path, {"shortcuts": {"0": shortcut(111, "Existing Game")}})
    patch = make_patch(path, {"shortcuts": {"1": shortcut(222, "New Game")}})

    assert patch_binary_keyvalues(patch)

    result = read_shortcuts(path)
    assert result["shortcuts"]["0"]["AppName"] == "Existing Game"
    assert result["shortcuts"]["1"]["AppName"] == "New Game"
    assert result["shortcuts"]["1"]["appid"] == 222


def test_updates_existing_shortcut_field(fake_steam, tmp_path):
    path = tmp_path / "shortcuts.vdf"
    write_shortcuts(path, {"shortcuts": {"0": shortcut(111, "Game")}})
    patch = make_patch(path, {"shortcuts": {"0": {"LaunchOptions": "wrapper %command%"}}})

    assert patch_binary_keyvalues(patch)

    result = read_shortcuts(path)
    assert result["shortcuts"]["0"]["LaunchOptions"] == "wrapper %command%"
    assert result["shortcuts"]["0"]["AppName"] == "Game"


def test_unchanged_data_skips_write_and_steam_check(fake_steam, tmp_path):
    path = tmp_path / "shortcuts.vdf"
    write_shortcuts(path, {"shortcuts": {"0": shortcut(111, "Game")}})
    original_bytes = path.read_bytes()
    patch = make_patch(path, {"shortcuts": {"0": shortcut(111, "Game")}})

    assert patch_binary_keyvalues(patch)

    assert path.read_bytes() == original_bytes
    assert fake_steam.calls == []


def test_blocked_while_steam_running(fake_steam, tmp_path):
    fake_steam.running = True
    path = tmp_path / "shortcuts.vdf"
    write_shortcuts(path, {"shortcuts": {"0": shortcut(111, "Game")}})
    original_bytes = path.read_bytes()
    patch = make_patch(path, {"shortcuts": {"1": shortcut(222, "New Game")}})

    assert not patch_binary_keyvalues(patch)

    assert path.read_bytes() == original_bytes
    assert fake_steam.calls == [False]


def test_close_steam_closes_and_writes(fake_steam, tmp_path):
    fake_steam.running = True
    path = tmp_path / "shortcuts.vdf"
    write_shortcuts(path, {"shortcuts": {}})
    patch = make_patch(path, {"shortcuts": {"0": shortcut(111, "Game")}}, close_steam=True)

    assert patch_binary_keyvalues(patch)

    assert fake_steam.calls == [True]
    assert read_shortcuts(path)["shortcuts"]["0"]["appid"] == 111


def test_missing_file_is_skipped(fake_steam, tmp_path):
    path = tmp_path / "shortcuts.vdf"
    patch = make_patch(path, {"shortcuts": {"0": shortcut(111, "Game")}})

    assert patch_binary_keyvalues(patch)

    assert not path.exists()


def test_empty_file_is_patched(fake_steam, tmp_path):
    path = tmp_path / "shortcuts.vdf"
    path.write_bytes(b"")
    patch = make_patch(path, {"shortcuts": {"0": shortcut(111, "Game")}})

    assert patch_binary_keyvalues(patch)

    assert read_shortcuts(path)["shortcuts"]["0"]["AppName"] == "Game"


def test_deletion_removes_shortcut(fake_steam, tmp_path):
    path = tmp_path / "shortcuts.vdf"
    write_shortcuts(
        path,
        {"shortcuts": {"0": shortcut(111, "Keep"), "1": shortcut(222, "Remove")}},
    )
    patch = make_patch(path, {}, deletions=[Deletion(key_path=("shortcuts", "1"))])

    assert patch_binary_keyvalues(patch)

    result = read_shortcuts(path)
    assert "1" not in result["shortcuts"]
    assert result["shortcuts"]["0"]["AppName"] == "Keep"


@requires_patched_vdf
def test_generated_appid_range_roundtrip(fake_steam, tmp_path):
    appid = 0x914B9DA1
    path = tmp_path / "shortcuts.vdf"
    write_shortcuts(path, {"shortcuts": {}})
    patch = make_patch(path, {"shortcuts": {"0": shortcut(appid, "Game")}})

    assert patch_binary_keyvalues(patch)

    assert read_shortcuts(path)["shortcuts"]["0"]["appid"] == appid
