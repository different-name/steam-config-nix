import psutil
import pytest

from steam_config_patcher.steam import get_steam_user_ids, steam_is_closed


class FakeProc:
    def __init__(self, name, hangs=False):
        self._name = name
        self.hangs = hangs
        self.terminated = False
        self.killed = False

    def name(self):
        return self._name

    def terminate(self):
        self.terminated = True

    def wait(self, timeout=None):
        if self.hangs:
            raise psutil.TimeoutExpired(timeout)

    def kill(self):
        self.killed = True


@pytest.fixture
def fake_procs(monkeypatch):
    procs = []
    monkeypatch.setattr(
        "steam_config_patcher.steam.psutil.process_iter",
        lambda *args, **kwargs: procs,
    )
    monkeypatch.setattr("steam_config_patcher.steam.time.sleep", lambda seconds: None)
    return procs


def test_user_ids_are_numeric_dirs_excluding_zero(tmp_path):
    userdata = tmp_path / "userdata"
    for name in ("111", "222", "0", "ac", "anonymous"):
        (userdata / name).mkdir(parents=True)
    (userdata / "333").touch()

    assert sorted(get_steam_user_ids(tmp_path)) == [111, 222]


def test_closed_when_no_steam_process(fake_procs):
    fake_procs.append(FakeProc("systemd"))

    assert steam_is_closed()


def test_running_steam_reports_not_closed(fake_procs):
    proc = FakeProc("steam")
    fake_procs.append(proc)

    assert not steam_is_closed()

    assert not proc.terminated


def test_close_if_running_terminates_steam(fake_procs):
    proc = FakeProc("steam")
    fake_procs.append(proc)

    assert steam_is_closed(close_if_running=True)

    assert proc.terminated
    assert not proc.killed


def test_close_if_running_kills_unresponsive_steam(fake_procs):
    proc = FakeProc("steam", hangs=True)
    fake_procs.append(proc)

    assert steam_is_closed(close_if_running=True)

    assert proc.terminated
    assert proc.killed
