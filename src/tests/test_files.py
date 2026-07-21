import os
from types import SimpleNamespace

import pytest

from steam_config_patcher.files import apply_file_ops
from steam_config_patcher.files_manifest import backup_path, load_files_manifest
from steam_config_patcher.types import FileOp, RemoveOp


@pytest.fixture
def env(tmp_path, monkeypatch):
    steam_dir = tmp_path / "steam"
    (steam_dir / "config").mkdir(parents=True)
    install = tmp_path / "install"
    install.mkdir()
    prefix = tmp_path / "prefix"
    prefix.mkdir()
    src = tmp_path / "src"
    src.mkdir()

    monkeypatch.setattr(
        "steam_config_patcher.files.find_app_install_dir",
        lambda sd, aid: install if install.is_dir() else None,
    )
    monkeypatch.setattr(
        "steam_config_patcher.files.find_app_compat_prefix",
        lambda sd, aid: prefix if prefix.is_dir() else None,
    )
    return SimpleNamespace(
        steam_dir=steam_dir, install=install, prefix=prefix, src=src
    )


def source_file(env, name, content="data", mode=0o644):
    path = env.src / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
    path.chmod(mode)
    return path


def place(env, target, source, location="install", overwrite_changes=True, executable=None):
    return FileOp(
        app_id=620,
        location=location,
        target=target,
        source=source,
        overwrite_changes=overwrite_changes,
        executable=executable,
    )


def test_place_new_file_copies_writable(env):
    src = source_file(env, "foo.dll", "modcontent", mode=0o444)

    apply_file_ops(env.steam_dir, [place(env, "Mods/foo.dll", src)], [])

    target = env.install / "Mods" / "foo.dll"
    assert target.read_text() == "modcontent"
    assert os.access(target, os.W_OK)
    files = load_files_manifest(env.steam_dir).files
    assert len(files) == 1
    assert files[0].op == "place" and not files[0].had_backup


def test_replace_backs_up_original_and_reverts(env):
    target = env.install / "base.pak"
    target.write_text("vanilla")
    src = source_file(env, "mod.pak", "modded")

    apply_file_ops(env.steam_dir, [place(env, "base.pak", src)], [])

    assert target.read_text() == "modded"
    assert backup_path(env.steam_dir, 620, "install", "base.pak").read_text() == "vanilla"

    apply_file_ops(env.steam_dir, [], [])

    assert target.read_text() == "vanilla"
    assert load_files_manifest(env.steam_dir).files == []


def test_created_file_deleted_on_revert_with_empty_dir_cleanup(env):
    src = source_file(env, "foo.dll", "x")
    apply_file_ops(env.steam_dir, [place(env, "Mods/foo.dll", src)], [])

    apply_file_ops(env.steam_dir, [], [])

    assert not (env.install / "Mods" / "foo.dll").exists()
    assert not (env.install / "Mods").exists()


def test_directory_merge_keeps_existing_files(env):
    (env.install / "Mods").mkdir()
    (env.install / "Mods" / "vanilla.dll").write_text("v")
    source_file(env, "tree/a.dll", "A")
    source_file(env, "tree/sub/b.dll", "B")

    apply_file_ops(env.steam_dir, [place(env, "Mods", env.src / "tree")], [])

    assert (env.install / "Mods" / "vanilla.dll").read_text() == "v"
    assert (env.install / "Mods" / "a.dll").read_text() == "A"
    assert (env.install / "Mods" / "sub" / "b.dll").read_text() == "B"


def test_seed_writes_once_and_preserves_edits(env):
    src = source_file(env, "cfg.ini", "default")
    op = place(env, "cfg.ini", src, overwrite_changes=False)
    apply_file_ops(env.steam_dir, [op], [])
    target = env.install / "cfg.ini"
    target.write_text("user-edited")

    apply_file_ops(env.steam_dir, [op], [])

    assert target.read_text() == "user-edited"


def test_seed_revert_leaves_user_edits_deletes_unmodified(env):
    src = source_file(env, "cfg.ini", "default")
    op = place(env, "cfg.ini", src, overwrite_changes=False)

    apply_file_ops(env.steam_dir, [op], [])
    apply_file_ops(env.steam_dir, [], [])
    assert not (env.install / "cfg.ini").exists()

    apply_file_ops(env.steam_dir, [op], [])
    (env.install / "cfg.ini").write_text("mine")
    apply_file_ops(env.steam_dir, [], [])
    assert (env.install / "cfg.ini").read_text() == "mine"


def test_executable_inherited_and_forced(env):
    plain = source_file(env, "plain", "x", mode=0o644)
    exe = source_file(env, "exe", "x", mode=0o755)

    apply_file_ops(
        env.steam_dir,
        [
            place(env, "plain", plain),
            place(env, "exe", exe),
            place(env, "forced", plain, executable=True),
            place(env, "unforced", exe, executable=False),
        ],
        [],
    )

    assert not os.access(env.install / "plain", os.X_OK)
    assert os.access(env.install / "exe", os.X_OK)
    assert os.access(env.install / "forced", os.X_OK)
    assert not os.access(env.install / "unforced", os.X_OK)


def test_remove_file_backs_up_and_reverts(env):
    (env.install / "broken.dll").write_text("bad")

    apply_file_ops(env.steam_dir, [], [RemoveOp(620, "install", "broken.dll")])
    assert not (env.install / "broken.dll").exists()

    apply_file_ops(env.steam_dir, [], [])
    assert (env.install / "broken.dll").read_text() == "bad"


def test_remove_directory_recursive_and_reverts(env):
    junk = env.install / "junk"
    (junk / "sub").mkdir(parents=True)
    (junk / "a").write_text("a")
    (junk / "sub" / "b").write_text("b")

    apply_file_ops(env.steam_dir, [], [RemoveOp(620, "install", "junk")])
    assert not (junk / "a").exists() and not (junk / "sub" / "b").exists()

    apply_file_ops(env.steam_dir, [], [])
    assert (junk / "a").read_text() == "a"
    assert (junk / "sub" / "b").read_text() == "b"


def test_remove_symlink_to_directory_does_not_crash(env):
    real_dir = env.install / "realdir"
    real_dir.mkdir()
    (real_dir / "file").write_text("data")
    link = env.install / "link"
    link.symlink_to(real_dir)

    apply_file_ops(env.steam_dir, [], [RemoveOp(620, "install", "link")])

    assert not link.is_symlink()
    assert (real_dir / "file").read_text() == "data"

    apply_file_ops(env.steam_dir, [], [])

    assert link.is_symlink()


def test_remove_revert_leaves_recreated_file(env):
    target = env.install / "broken.dll"
    target.write_text("original")
    apply_file_ops(env.steam_dir, [], [RemoveOp(620, "install", "broken.dll")])
    assert not target.exists()

    target.write_text("recreated by game")
    apply_file_ops(env.steam_dir, [], [])

    assert target.read_text() == "recreated by game"


def test_place_revert_leaves_game_written_content_on_created_path(env):
    src = source_file(env, "mod.dll", "mine")
    op = place(env, "new/mod.dll", src)
    apply_file_ops(env.steam_dir, [op], [])
    target = env.install / "new" / "mod.dll"

    target.write_text("game content")
    apply_file_ops(env.steam_dir, [], [])

    assert target.read_text() == "game content"


def test_mirror_via_remove_keeps_placed_removes_vanilla(env):
    mods = env.install / "Mods"
    mods.mkdir()
    (mods / "vanilla.dll").write_text("v")
    src = source_file(env, "mymod.dll", "mine")

    apply_file_ops(
        env.steam_dir,
        [place(env, "Mods/mymod.dll", src)],
        [RemoveOp(620, "install", "Mods")],
    )

    assert (mods / "mymod.dll").read_text() == "mine"
    assert not (mods / "vanilla.dll").exists()


def test_specific_file_overrides_directory_entry(env):
    source_file(env, "tree/a.cfg", "from-tree")
    override = source_file(env, "override.cfg", "specific")

    apply_file_ops(
        env.steam_dir,
        [
            place(env, "Mods", env.src / "tree"),
            place(env, "Mods/a.cfg", override),
        ],
        [],
    )

    assert (env.install / "Mods" / "a.cfg").read_text() == "specific"


def test_root_not_found_skips_and_keeps_prev(env, monkeypatch):
    src = source_file(env, "foo.dll", "x")
    apply_file_ops(env.steam_dir, [place(env, "foo.dll", src)], [])

    monkeypatch.setattr(
        "steam_config_patcher.files.find_app_install_dir", lambda sd, aid: None
    )
    apply_file_ops(env.steam_dir, [place(env, "foo.dll", src)], [])

    assert len(load_files_manifest(env.steam_dir).files) == 1


def test_overwrite_changes_re_enforces_drifted_target(env):
    src = source_file(env, "mod.dll", "mine")
    op = place(env, "Mods/mod.dll", src)
    apply_file_ops(env.steam_dir, [op], [])
    target = env.install / "Mods" / "mod.dll"

    target.write_text("clobbered by a game update")
    apply_file_ops(env.steam_dir, [op], [])

    assert target.read_text() == "mine"


def test_overwrite_changes_re_enforces_exec_bit(env):
    src = source_file(env, "run.sh", "x", mode=0o755)
    op = place(env, "run.sh", src, executable=True)
    apply_file_ops(env.steam_dir, [op], [])
    target = env.install / "run.sh"

    target.chmod(0o644)
    apply_file_ops(env.steam_dir, [op], [])

    assert os.access(target, os.X_OK)


def test_seed_does_not_re_enforce_drift(env):
    src = source_file(env, "cfg.ini", "default")
    op = place(env, "cfg.ini", src, overwrite_changes=False)
    apply_file_ops(env.steam_dir, [op], [])
    target = env.install / "cfg.ini"

    target.write_text("user edit")
    apply_file_ops(env.steam_dir, [op], [])

    assert target.read_text() == "user edit"


def test_reapply_is_stable(env):
    src = source_file(env, "foo.dll", "x")
    op = place(env, "Mods/foo.dll", src)

    apply_file_ops(env.steam_dir, [op], [])
    first = load_files_manifest(env.steam_dir)
    apply_file_ops(env.steam_dir, [op], [])
    second = load_files_manifest(env.steam_dir)

    assert first == second
    assert (env.install / "Mods" / "foo.dll").read_text() == "x"


def test_stale_source_file_is_reverted_on_update(env):
    a = source_file(env, "a.dll", "A")
    b = source_file(env, "b.dll", "B")
    apply_file_ops(
        env.steam_dir, [place(env, "a.dll", a), place(env, "b.dll", b)], []
    )

    apply_file_ops(env.steam_dir, [place(env, "a.dll", a)], [])

    assert (env.install / "a.dll").exists()
    assert not (env.install / "b.dll").exists()


def test_prefix_location_targets_prefix_root(env):
    src = source_file(env, "cfg", "x")

    apply_file_ops(
        env.steam_dir, [place(env, "drive_c/cfg", src, location="prefix")], []
    )

    assert (env.prefix / "drive_c" / "cfg").read_text() == "x"


def test_revert_leaves_preexisting_empty_dir(env):
    existing = env.install / "logs"
    existing.mkdir()
    src = source_file(env, "run.log", "x")
    op = place(env, "logs/run.log", src)

    apply_file_ops(env.steam_dir, [op], [])
    apply_file_ops(env.steam_dir, [], [])

    assert not (existing / "run.log").exists()
    assert existing.is_dir()


def test_revert_removes_created_dir(env):
    src = source_file(env, "foo.dll", "x")
    op = place(env, "new/deep/foo.dll", src)

    apply_file_ops(env.steam_dir, [op], [])
    assert (env.install / "new" / "deep").is_dir()

    apply_file_ops(env.steam_dir, [], [])
    assert not (env.install / "new").exists()


def test_orphan_backup_deleted_when_game_uninstalled(env, monkeypatch):
    target = env.install / "base.pak"
    target.write_text("vanilla")
    src = source_file(env, "mod.pak", "modded")
    op = place(env, "base.pak", src)

    apply_file_ops(env.steam_dir, [op], [])
    stored = backup_path(env.steam_dir, 620, "install", "base.pak")
    assert stored.exists()

    monkeypatch.setattr(
        "steam_config_patcher.files.find_app_install_dir", lambda sd, aid: None
    )
    apply_file_ops(env.steam_dir, [], [])

    assert not stored.exists()
    assert load_files_manifest(env.steam_dir).files == []


def test_stale_backup_deleted_when_user_modified(env):
    target = env.install / "base.pak"
    target.write_text("vanilla")
    src = source_file(env, "mod.pak", "modded")
    op = place(env, "base.pak", src)

    apply_file_ops(env.steam_dir, [op], [])
    target.write_text("user-edited")
    apply_file_ops(env.steam_dir, [], [])

    assert target.read_text() == "user-edited"
    assert not backup_path(env.steam_dir, 620, "install", "base.pak").exists()
