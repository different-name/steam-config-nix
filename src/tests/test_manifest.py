import json

from steam_config_patcher.manifest import load_manifest, manifest_path, save_manifest
from steam_config_patcher.types import UserManifest


def make_user_dir(tmp_path, user_id=111):
    steam_dir = tmp_path / "steam"
    (steam_dir / "userdata" / str(user_id) / "config").mkdir(parents=True)
    return steam_dir


def test_round_trip(tmp_path):
    steam_dir = make_user_dir(tmp_path)
    manifest = UserManifest(
        compat_tools={0: "proton_experimental", 1091500: "GE-Proton"},
        launch_options={620: "wrapper %command%"},
        shortcuts=[2434605777],
    )

    save_manifest(steam_dir, 111, manifest)

    assert load_manifest(steam_dir, 111) == manifest


def test_saved_file_is_versioned_json(tmp_path):
    steam_dir = make_user_dir(tmp_path)

    save_manifest(steam_dir, 111, UserManifest(compat_tools={620: "GE-Proton"}))

    raw = json.loads(manifest_path(steam_dir, 111).read_text(encoding="utf-8"))
    assert raw["version"] == 1
    assert raw["compat_tools"] == {"620": "GE-Proton"}


def test_load_missing_file_returns_empty(tmp_path):
    steam_dir = make_user_dir(tmp_path)

    assert load_manifest(steam_dir, 111) == UserManifest()


def test_load_corrupt_file_returns_empty(tmp_path):
    steam_dir = make_user_dir(tmp_path)
    manifest_path(steam_dir, 111).write_text("not json", encoding="utf-8")

    assert load_manifest(steam_dir, 111) == UserManifest()


def test_load_tolerates_missing_fields(tmp_path):
    steam_dir = make_user_dir(tmp_path)
    manifest_path(steam_dir, 111).write_text('{"version": 1}', encoding="utf-8")

    assert load_manifest(steam_dir, 111) == UserManifest()


def test_save_skips_when_user_config_dir_missing(tmp_path):
    steam_dir = tmp_path / "steam"

    save_manifest(steam_dir, 111, UserManifest(compat_tools={620: "GE-Proton"}))

    assert not manifest_path(steam_dir, 111).exists()


def test_save_leaves_no_tmp_file(tmp_path):
    steam_dir = make_user_dir(tmp_path)

    save_manifest(steam_dir, 111, UserManifest())

    config_dir = manifest_path(steam_dir, 111).parent
    assert [p.name for p in config_dir.iterdir()] == [manifest_path(steam_dir, 111).name]
