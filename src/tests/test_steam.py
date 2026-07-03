import os
from types import SimpleNamespace

import pytest

from steam_config_patcher.steam import (
    close_steam,
    find_app_manifest,
    game_is_running,
    get_steam_dir,
    get_steam_user_ids,
    steam_is_running,
    steam_library_paths,
    wait_for_game_exit,
    wait_for_steam_exit,
)


class FakeProc:
    def __init__(self, name, uid=None, hangs=False, unkillable=False, cmdline=()):
        self.info = {"name": name, "cmdline": list(cmdline)}
        self._uid = os.getuid() if uid is None else uid
        self.hangs = hangs
        self.unkillable = unkillable
        self.alive = True
        self.terminated = False
        self.killed = False

    def uids(self):
        return SimpleNamespace(real=self._uid)

    def terminate(self):
        self.terminated = True
        if not self.hangs:
            self.alive = False

    def kill(self):
        self.killed = True
        if not self.unkillable:
            self.alive = False


@pytest.fixture
def fake_system(monkeypatch):
    system = SimpleNamespace(procs=[], commands=[], steam_bin=None, shutdown_works=True)

    def fake_run(cmd, **kwargs):
        system.commands.append(cmd)
        if system.shutdown_works:
            for proc in system.procs:
                proc.alive = False
        return SimpleNamespace(returncode=0)

    def fake_wait_procs(procs, timeout=None):
        if timeout is None:
            for proc in procs:
                proc.alive = False
        gone = [p for p in procs if not p.alive]
        alive = [p for p in procs if p.alive]
        return gone, alive

    monkeypatch.setattr(
        "steam_config_patcher.steam.psutil.process_iter",
        lambda *args, **kwargs: [p for p in system.procs if p.alive],
    )
    monkeypatch.setattr("steam_config_patcher.steam.psutil.wait_procs", fake_wait_procs)
    monkeypatch.setattr("steam_config_patcher.steam.subprocess.run", fake_run)
    monkeypatch.setattr(
        "steam_config_patcher.steam.shutil.which", lambda name: system.steam_bin
    )
    monkeypatch.setattr("steam_config_patcher.steam.time.sleep", lambda seconds: None)
    return system


def test_steam_dir_prefers_dot_steam_root_symlink(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path))
    install = tmp_path / "steam-install"
    install.mkdir()
    (tmp_path / ".steam").mkdir()
    (tmp_path / ".steam" / "root").symlink_to(install)
    (tmp_path / ".local" / "share" / "Steam").mkdir(parents=True)

    assert get_steam_dir() == install.resolve()


def test_steam_dir_falls_back_to_data_dir(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path))
    data_dir = tmp_path / ".local" / "share" / "Steam"
    data_dir.mkdir(parents=True)

    assert get_steam_dir() == data_dir.resolve()


def test_steam_dir_missing_raises(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path))

    with pytest.raises(FileNotFoundError):
        get_steam_dir()


def write_libraryfolders(steam_dir, library_paths):
    (steam_dir / "config").mkdir(parents=True, exist_ok=True)
    blocks = "".join(
        f'\t"{index}"\n\t{{\n\t\t"path"\t\t"{path}"\n\t}}\n'
        for index, path in enumerate(library_paths)
    )
    (steam_dir / "config" / "libraryfolders.vdf").write_text(
        f'"libraryfolders"\n{{\n{blocks}}}\n', encoding="utf-8"
    )


def test_library_paths_include_steam_dir_and_extra_libraries(tmp_path):
    steam_dir = tmp_path / "steam"
    extra = tmp_path / "drive"
    write_libraryfolders(steam_dir, [steam_dir, extra])

    assert steam_library_paths(steam_dir) == [steam_dir, extra]


def test_library_paths_without_libraryfolders(tmp_path):
    steam_dir = tmp_path / "steam"
    steam_dir.mkdir()

    assert steam_library_paths(steam_dir) == [steam_dir]


def test_find_app_manifest_searches_all_libraries(tmp_path):
    steam_dir = tmp_path / "steam"
    extra = tmp_path / "drive"
    write_libraryfolders(steam_dir, [steam_dir, extra])
    manifest = extra / "steamapps" / "appmanifest_620.acf"
    manifest.parent.mkdir(parents=True)
    manifest.touch()

    assert find_app_manifest(steam_dir, 620) == manifest


def test_find_app_manifest_missing_returns_none(tmp_path):
    steam_dir = tmp_path / "steam"
    (steam_dir / "steamapps").mkdir(parents=True)

    assert find_app_manifest(steam_dir, 620) is None


def test_user_ids_are_numeric_dirs_excluding_zero(tmp_path):
    userdata = tmp_path / "userdata"
    for name in ("111", "222", "0", "ac", "anonymous"):
        (userdata / name).mkdir(parents=True)
    (userdata / "333").touch()

    assert sorted(get_steam_user_ids(tmp_path)) == [111, 222]


def test_not_running_without_steam_process(fake_system):
    fake_system.procs.append(FakeProc("systemd"))

    assert not steam_is_running()


def test_running_with_steam_process(fake_system):
    fake_system.procs.append(FakeProc("steam"))

    assert steam_is_running()


def test_other_users_steam_is_ignored(fake_system):
    fake_system.procs.append(FakeProc("steam", uid=os.getuid() + 1))

    assert not steam_is_running()


def test_close_uses_steam_shutdown_when_available(fake_system):
    proc = FakeProc("steam")
    fake_system.procs.append(proc)
    fake_system.steam_bin = "/run/current-system/sw/bin/steam"

    close_steam()

    assert fake_system.commands == [[fake_system.steam_bin, "-shutdown"]]
    assert not proc.terminated
    assert not proc.killed


def test_close_terminates_when_no_steam_binary(fake_system):
    proc = FakeProc("steam")
    fake_system.procs.append(proc)

    close_steam()

    assert fake_system.commands == []
    assert proc.terminated
    assert not proc.killed


def test_close_escalates_when_shutdown_does_nothing(fake_system):
    proc = FakeProc("steam")
    fake_system.procs.append(proc)
    fake_system.steam_bin = "/run/current-system/sw/bin/steam"
    fake_system.shutdown_works = False

    close_steam()

    assert fake_system.commands == [[fake_system.steam_bin, "-shutdown"]]
    assert proc.terminated


def test_close_kills_unresponsive_steam(fake_system):
    proc = FakeProc("steam", hangs=True)
    fake_system.procs.append(proc)

    close_steam()

    assert proc.terminated
    assert proc.killed


def test_close_without_steam_running_does_nothing(fake_system):
    close_steam()

    assert fake_system.commands == []


def test_game_running_detects_reaper(fake_system):
    fake_system.procs.append(
        FakeProc("reaper", cmdline=["reaper", "SteamLaunch", "AppId=1091500", "--", "game"])
    )

    assert game_is_running()


def test_game_not_running_without_reaper(fake_system):
    fake_system.procs.append(FakeProc("steam"))

    assert not game_is_running()


def test_other_users_game_is_ignored(fake_system):
    fake_system.procs.append(
        FakeProc(
            "reaper",
            uid=os.getuid() + 1,
            cmdline=["reaper", "SteamLaunch", "AppId=1", "--", "game"],
        )
    )

    assert not game_is_running()


def test_wait_for_game_exit_returns_without_closing(fake_system):
    proc = FakeProc("reaper", cmdline=["reaper", "SteamLaunch", "AppId=1", "--", "game"])
    fake_system.procs.append(proc)

    wait_for_game_exit()

    assert not proc.terminated
    assert not proc.killed


def test_wait_for_steam_exit_returns_without_closing(fake_system):
    proc = FakeProc("steam")
    fake_system.procs.append(proc)

    wait_for_steam_exit()

    assert not proc.terminated
    assert not proc.killed
    assert fake_system.commands == []
