import configparser
import json
from types import SimpleNamespace

import pytest

from steam_config_patcher.files import apply_file_ops
from steam_config_patcher.files_manifest import backup_path, load_files_manifest
from steam_config_patcher.types import PatchOp, RemoveOp


@pytest.fixture
def env(tmp_path, monkeypatch):
    steam_dir = tmp_path / "steam"
    (steam_dir / "config").mkdir(parents=True)
    install = tmp_path / "install"
    install.mkdir()
    prefix = tmp_path / "prefix"
    prefix.mkdir()

    monkeypatch.setattr(
        "steam_config_patcher.files.find_app_install_dir",
        lambda sd, aid: install if install.is_dir() else None,
    )
    monkeypatch.setattr(
        "steam_config_patcher.files.find_app_compat_prefix",
        lambda sd, aid: prefix if prefix.is_dir() else None,
    )
    return SimpleNamespace(steam_dir=steam_dir, install=install, prefix=prefix)


def patch(env, target, content, fmt="json", location="game", when_missing="create"):
    return PatchOp(
        app_id=620,
        location=location,
        target=target,
        format=fmt,
        content=content,
        when_missing=when_missing,
    )


def read_ini(path):
    parser = configparser.ConfigParser(interpolation=None)
    parser.optionxform = str
    parser.read_string(path.read_text())
    return parser


def test_json_create_when_missing(env):
    apply_file_ops(
        env.steam_dir, [], [], [patch(env, "settings.json", {"Fullscreen": True})]
    )

    target = env.install / "settings.json"
    assert json.loads(target.read_text()) == {"Fullscreen": True}
    files = load_files_manifest(env.steam_dir).files
    assert len(files) == 1
    assert files[0].op == "patch" and not files[0].had_backup


def test_json_merge_preserves_untouched_keys(env):
    target = env.install / "settings.json"
    target.write_text(json.dumps({"Width": 1920, "Volume": 50}))

    apply_file_ops(
        env.steam_dir,
        [],
        [],
        [patch(env, "settings.json", {"Volume": 100, "Fullscreen": True})],
    )

    assert json.loads(target.read_text()) == {
        "Width": 1920,
        "Volume": 100,
        "Fullscreen": True,
    }
    files = load_files_manifest(env.steam_dir).files
    assert files[0].had_backup


def test_json_deep_merges_nested_objects(env):
    target = env.install / "settings.json"
    target.write_text(
        json.dumps({"graphics": {"width": 800, "height": 600}, "audio": {"volume": 5}})
    )

    apply_file_ops(
        env.steam_dir,
        [],
        [],
        [patch(env, "settings.json", {"graphics": {"height": 1080, "vsync": True}})],
    )

    assert json.loads(target.read_text()) == {
        "graphics": {"width": 800, "height": 1080, "vsync": True},
        "audio": {"volume": 5},
    }


def test_ini_create_when_missing(env):
    apply_file_ops(
        env.steam_dir,
        [],
        [],
        [patch(env, "cfg.ini", {"Display": {"Fullscreen": 1, "Width": 1920}}, fmt="ini")],
    )

    parser = read_ini(env.install / "cfg.ini")
    assert parser["Display"]["Fullscreen"] == "1"
    assert parser["Display"]["Width"] == "1920"


def test_ini_merge_preserves_other_sections_case_and_percent(env):
    target = env.install / "cfg.ini"
    target.write_text(
        "[Audio]\n"
        "Volume = 50\n"
        "\n"
        "[Display]\n"
        "MixedCaseKey = 800\n"
        "SavePath = C:\\Games\\%USER%\\save\n"
    )

    apply_file_ops(
        env.steam_dir,
        [],
        [],
        [patch(env, "cfg.ini", {"Display": {"Fullscreen": 1}}, fmt="ini")],
    )

    parser = read_ini(target)
    assert parser["Audio"]["Volume"] == "50"
    assert parser["Display"]["MixedCaseKey"] == "800"
    assert parser["Display"]["Fullscreen"] == "1"
    # key case preserved (not lowercased) and % kept literal
    raw = target.read_text()
    assert "MixedCaseKey" in raw
    assert "C:\\Games\\%USER%\\save" in raw


def test_skip_when_missing_writes_nothing_then_retries(env, capsys):
    op = patch(env, "settings.json", {"Fullscreen": True}, when_missing="skip")

    apply_file_ops(env.steam_dir, [], [], [op])

    target = env.install / "settings.json"
    assert not target.exists()
    assert load_files_manifest(env.steam_dir).files == []
    assert "waiting for settings.json" in capsys.readouterr().out

    # once the game creates the file, the next activation patches it
    target.write_text(json.dumps({"Width": 1920}))
    apply_file_ops(env.steam_dir, [], [], [op])

    assert json.loads(target.read_text()) == {"Width": 1920, "Fullscreen": True}


def test_reenforce_reapplies_drift_each_activation(env):
    target = env.install / "settings.json"
    target.write_text(json.dumps({"Fullscreen": True}))
    op = patch(env, "settings.json", {"Fullscreen": True})
    apply_file_ops(env.steam_dir, [], [], [op])

    target.write_text(json.dumps({"Fullscreen": False, "Extra": 1}))
    apply_file_ops(env.steam_dir, [], [], [op])

    data = json.loads(target.read_text())
    assert data["Fullscreen"] is True
    assert data["Extra"] == 1


def test_reapply_is_stable(env):
    target = env.install / "settings.json"
    target.write_text(json.dumps({"Width": 1920}))
    op = patch(env, "settings.json", {"Fullscreen": True})

    apply_file_ops(env.steam_dir, [], [], [op])
    first = load_files_manifest(env.steam_dir)
    apply_file_ops(env.steam_dir, [], [], [op])
    second = load_files_manifest(env.steam_dir)

    assert first == second


def test_reversal_restores_original_backup(env):
    target = env.install / "settings.json"
    target.write_text(json.dumps({"Fullscreen": False}))
    op = patch(env, "settings.json", {"Fullscreen": True})

    apply_file_ops(env.steam_dir, [], [], [op])
    assert json.loads(target.read_text())["Fullscreen"] is True
    assert backup_path(env.steam_dir, 620, "game", "settings.json").exists()

    apply_file_ops(env.steam_dir, [], [], [])

    assert json.loads(target.read_text()) == {"Fullscreen": False}
    assert load_files_manifest(env.steam_dir).files == []
    assert not backup_path(env.steam_dir, 620, "game", "settings.json").exists()


def test_reversal_removes_created_file_and_cleans_dir(env):
    op = patch(env, "sub/settings.json", {"Fullscreen": True})
    apply_file_ops(env.steam_dir, [], [], [op])
    target = env.install / "sub" / "settings.json"
    assert target.exists()

    apply_file_ops(env.steam_dir, [], [], [])

    assert not target.exists()
    assert not (env.install / "sub").exists()


def test_reversal_leaves_user_changed_file(env):
    target = env.install / "settings.json"
    target.write_text(json.dumps({"Fullscreen": False}))
    op = patch(env, "settings.json", {"Fullscreen": True})
    apply_file_ops(env.steam_dir, [], [], [op])

    target.write_text(json.dumps({"Fullscreen": True, "Mine": 1}))
    apply_file_ops(env.steam_dir, [], [], [])

    assert json.loads(target.read_text()) == {"Fullscreen": True, "Mine": 1}
    assert not backup_path(env.steam_dir, 620, "game", "settings.json").exists()


def test_removefiles_does_not_delete_patched_target(env):
    config_dir = env.install / "Config"
    config_dir.mkdir()
    (config_dir / "settings.json").write_text(json.dumps({"a": 1}))
    (config_dir / "junk.txt").write_text("junk")

    apply_file_ops(
        env.steam_dir,
        [],
        [RemoveOp(620, "game", "Config")],
        [patch(env, "Config/settings.json", {"b": 2})],
    )

    settings = config_dir / "settings.json"
    assert settings.exists()
    assert json.loads(settings.read_text()) == {"a": 1, "b": 2}
    assert not (config_dir / "junk.txt").exists()


def test_prefix_location_targets_prefix_root(env):
    apply_file_ops(
        env.steam_dir,
        [],
        [],
        [patch(env, "drive_c/game.json", {"ok": True}, location="prefix")],
    )

    assert json.loads((env.prefix / "drive_c" / "game.json").read_text()) == {"ok": True}


def test_unsafe_patch_target_is_skipped(env):
    outside = env.install.parent / "escaped.json"

    apply_file_ops(env.steam_dir, [], [], [patch(env, "../escaped.json", {"x": 1})])

    assert not outside.exists()
    assert load_files_manifest(env.steam_dir).files == []


def test_root_not_found_skips_and_keeps_prev(env, monkeypatch):
    target = env.install / "settings.json"
    target.write_text(json.dumps({"a": 1}))
    op = patch(env, "settings.json", {"b": 2})
    apply_file_ops(env.steam_dir, [], [], [op])

    monkeypatch.setattr(
        "steam_config_patcher.files.find_app_install_dir", lambda sd, aid: None
    )
    apply_file_ops(env.steam_dir, [], [], [op])

    assert len(load_files_manifest(env.steam_dir).files) == 1
