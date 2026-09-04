import os

from steam_config_patcher.grid import apply_grid_art, desired_grid_files
from steam_config_patcher.types import GridArt


def make_source(tmp_path, name):
    path = tmp_path / name
    path.write_bytes(b"image")
    return str(path)


def grid_dir(steam_dir, user_id=111):
    return steam_dir / "userdata" / str(user_id) / "config" / "grid"


def test_desired_grid_files_maps_slots_and_extensions(tmp_path):
    art = GridArt(
        cover=make_source(tmp_path, "c.jpg"),
        header=make_source(tmp_path, "h.png"),
        hero=make_source(tmp_path, "hero.jpg"),
        logo=make_source(tmp_path, "logo.png"),
    )

    files = desired_grid_files({438100: art})

    assert set(files) == {
        "438100p.jpg",
        "438100.png",
        "438100_hero.jpg",
        "438100_logo.png",
    }


def test_desired_grid_files_skips_unset_slots(tmp_path):
    files = desired_grid_files({1: GridArt(hero=make_source(tmp_path, "h.jpg"))})

    assert set(files) == {"1_hero.jpg"}


def test_apply_creates_symlinks(tmp_path):
    steam_dir = tmp_path / "steam"
    source = make_source(tmp_path, "cover.jpg")
    desired = {"438100p.jpg": source}

    written = apply_grid_art(steam_dir, 111, desired, {})

    link = grid_dir(steam_dir) / "438100p.jpg"
    assert link.is_symlink()
    assert os.readlink(link) == source
    assert written == desired


def test_apply_is_idempotent(tmp_path):
    steam_dir = tmp_path / "steam"
    source = make_source(tmp_path, "cover.jpg")
    desired = {"438100p.jpg": source}

    apply_grid_art(steam_dir, 111, desired, {})
    link = grid_dir(steam_dir) / "438100p.jpg"
    before = link.lstat().st_ino

    apply_grid_art(steam_dir, 111, desired, desired)

    assert link.lstat().st_ino == before


def test_apply_updates_changed_source(tmp_path):
    steam_dir = tmp_path / "steam"
    old = make_source(tmp_path, "old.jpg")
    new = make_source(tmp_path, "new.jpg")

    apply_grid_art(steam_dir, 111, {"438100p.jpg": old}, {})
    apply_grid_art(steam_dir, 111, {"438100p.jpg": new}, {"438100p.jpg": old})

    assert os.readlink(grid_dir(steam_dir) / "438100p.jpg") == new


def test_cleanup_removes_our_stale_symlink(tmp_path):
    steam_dir = tmp_path / "steam"
    source = make_source(tmp_path, "hero.jpg")
    apply_grid_art(steam_dir, 111, {"438100_hero.jpg": source}, {})

    written = apply_grid_art(steam_dir, 111, {}, {"438100_hero.jpg": source})

    assert not (grid_dir(steam_dir) / "438100_hero.jpg").exists()
    assert written == {}


def test_cleanup_keeps_user_replaced_file(tmp_path):
    steam_dir = tmp_path / "steam"
    source = make_source(tmp_path, "hero.jpg")
    apply_grid_art(steam_dir, 111, {"438100_hero.jpg": source}, {})

    # user replaces our symlink with their own real file via Steam
    link = grid_dir(steam_dir) / "438100_hero.jpg"
    link.unlink()
    link.write_bytes(b"user art")

    apply_grid_art(steam_dir, 111, {}, {"438100_hero.jpg": source})

    assert link.is_file() and not link.is_symlink()
    assert link.read_bytes() == b"user art"


def test_apply_overwrites_manual_file_when_configured(tmp_path):
    steam_dir = tmp_path / "steam"
    grid_dir(steam_dir).mkdir(parents=True)
    manual = grid_dir(steam_dir) / "438100p.jpg"
    manual.write_bytes(b"manual")
    source = make_source(tmp_path, "cover.jpg")

    apply_grid_art(steam_dir, 111, {"438100p.jpg": source}, {})

    assert manual.is_symlink()
    assert os.readlink(manual) == source
