import json

from steam_config_patcher.files_manifest import backup_root, files_manifest_path
from steam_config_patcher.manifest import manifest_path
from steam_config_patcher.state import (
    legacy_backup_root,
    legacy_files_manifest_path,
    legacy_manifest_path,
    relocate_state,
    state_base,
)


def make_steam_dir(tmp_path, user_id=111):
    steam_dir = tmp_path / "steam"
    (steam_dir / "config").mkdir(parents=True)
    (steam_dir / "userdata" / str(user_id) / "config").mkdir(parents=True)
    return steam_dir


def test_a_user_manifest_moves_out_of_steams_directory(tmp_path):
    steam_dir = make_steam_dir(tmp_path)
    legacy = legacy_manifest_path(steam_dir, 111)
    legacy.write_text(json.dumps({"version": 2}), encoding="utf-8")

    relocate_state(steam_dir, [111])

    assert not legacy.exists()
    assert json.loads(manifest_path(steam_dir, 111).read_text()) == {"version": 2}


def test_the_files_manifest_and_its_backups_move_together(tmp_path):
    steam_dir = make_steam_dir(tmp_path)
    legacy_files_manifest_path(steam_dir).write_text(
        json.dumps({"version": 1, "files": [], "dirs": []}), encoding="utf-8"
    )
    kept = legacy_backup_root(steam_dir) / "620" / "game" / "cfg" / "user.ini"
    kept.parent.mkdir(parents=True)
    kept.write_text("vanilla", encoding="utf-8")

    relocate_state(steam_dir, [111])

    assert not legacy_files_manifest_path(steam_dir).exists()
    assert not legacy_backup_root(steam_dir).exists()
    assert files_manifest_path(steam_dir).is_file()
    moved = backup_root(steam_dir) / "620" / "game" / "cfg" / "user.ini"
    assert moved.read_text() == "vanilla"


def test_nothing_of_ours_is_left_under_the_steam_directory(tmp_path):
    steam_dir = make_steam_dir(tmp_path)
    legacy_manifest_path(steam_dir, 111).write_text("{}", encoding="utf-8")
    legacy_files_manifest_path(steam_dir).write_text("{}", encoding="utf-8")
    (legacy_backup_root(steam_dir) / "620").mkdir(parents=True)

    relocate_state(steam_dir, [111])

    assert [p.name for p in steam_dir.rglob("steam-config-nix*")] == []
    assert state_base() in manifest_path(steam_dir, 111).parents


def test_a_relocation_that_already_happened_is_left_alone(tmp_path):
    steam_dir = make_steam_dir(tmp_path)
    legacy_manifest_path(steam_dir, 111).write_text('{"version": 1}', encoding="utf-8")
    manifest_path(steam_dir, 111).parent.mkdir(parents=True)
    manifest_path(steam_dir, 111).write_text('{"version": 2}', encoding="utf-8")

    relocate_state(steam_dir, [111])

    assert json.loads(manifest_path(steam_dir, 111).read_text()) == {"version": 2}


def test_a_run_with_nothing_to_move_does_nothing(tmp_path):
    steam_dir = make_steam_dir(tmp_path)

    relocate_state(steam_dir, [111])

    assert not manifest_path(steam_dir, 111).exists()
    assert not files_manifest_path(steam_dir).exists()


# a rolled back generation writes backups to the legacy root again, and they are the only copy we hold
def test_legacy_backups_are_merged_into_an_existing_new_root(tmp_path):
    steam_dir = make_steam_dir(tmp_path)
    stranded = legacy_backup_root(steam_dir) / "620" / "game" / "cfg" / "user.ini"
    stranded.parent.mkdir(parents=True)
    stranded.write_text("vanilla", encoding="utf-8")
    already = backup_root(steam_dir) / "440" / "game" / "other.ini"
    already.parent.mkdir(parents=True)
    already.write_text("kept", encoding="utf-8")

    relocate_state(steam_dir, [111])

    assert not legacy_backup_root(steam_dir).exists()
    assert (backup_root(steam_dir) / "620" / "game" / "cfg" / "user.ini").read_text() == "vanilla"
    assert already.read_text() == "kept"


def test_a_legacy_backup_the_new_root_already_holds_is_left_alone(tmp_path):
    steam_dir = make_steam_dir(tmp_path)
    legacy = legacy_backup_root(steam_dir) / "620" / "game" / "user.ini"
    legacy.parent.mkdir(parents=True)
    legacy.write_text("older", encoding="utf-8")
    current = backup_root(steam_dir) / "620" / "game" / "user.ini"
    current.parent.mkdir(parents=True)
    current.write_text("newer", encoding="utf-8")

    relocate_state(steam_dir, [111])

    assert current.read_text() == "newer"
    assert legacy.read_text() == "older"
