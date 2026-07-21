import json

from steam_config_patcher.files_manifest import (
    backup_path,
    files_manifest_path,
    load_files_manifest,
    save_files_manifest,
)
from steam_config_patcher.types import ManagedFile


def make_config_dir(tmp_path):
    steam_dir = tmp_path / "steam"
    (steam_dir / "config").mkdir(parents=True)
    return steam_dir


def test_round_trip(tmp_path):
    steam_dir = make_config_dir(tmp_path)
    entries = [
        ManagedFile(
            app_id=620,
            location="install",
            target="Mods/foo.dll",
            op="place",
            source_hash="abc123",
            had_backup=True,
        ),
        ManagedFile(
            app_id=620,
            location="prefix",
            target="drive_c/stale.cfg",
            op="remove",
            had_backup=True,
        ),
    ]

    save_files_manifest(steam_dir, entries)

    assert load_files_manifest(steam_dir) == entries


def test_missing_manifest_is_empty(tmp_path):
    steam_dir = make_config_dir(tmp_path)

    assert load_files_manifest(steam_dir) == []


def test_unknown_version_is_ignored(tmp_path):
    steam_dir = make_config_dir(tmp_path)
    files_manifest_path(steam_dir).write_text(
        json.dumps({"version": 999, "files": [{"app_id": 1}]}), encoding="utf-8"
    )

    assert load_files_manifest(steam_dir) == []


def test_unreadable_manifest_is_ignored(tmp_path):
    steam_dir = make_config_dir(tmp_path)
    files_manifest_path(steam_dir).write_text("{ not json", encoding="utf-8")

    assert load_files_manifest(steam_dir) == []


def test_save_skips_when_config_dir_missing(tmp_path):
    steam_dir = tmp_path / "steam"

    save_files_manifest(steam_dir, [])

    assert not files_manifest_path(steam_dir).exists()


def test_backup_path_nests_by_app_and_location(tmp_path):
    steam_dir = make_config_dir(tmp_path)

    path = backup_path(steam_dir, 620, "install", "Mods/foo.dll")

    assert path == (
        steam_dir
        / "config"
        / "steam-config-nix-backups"
        / "620"
        / "install"
        / "Mods"
        / "foo.dll"
    )
