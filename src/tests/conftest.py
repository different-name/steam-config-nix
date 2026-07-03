import pytest


class FakeSteam:
    def __init__(self):
        self.running = False
        self.close_calls = 0
        self.on_close = None

    def is_running(self):
        return self.running

    def close(self):
        self.close_calls += 1
        self.running = False
        if self.on_close is not None:
            self.on_close()


@pytest.fixture
def fake_steam(monkeypatch):
    fake = FakeSteam()
    monkeypatch.setattr("steam_config_patcher.patcher.steam_is_running", fake.is_running)
    monkeypatch.setattr("steam_config_patcher.patcher.close_steam", fake.close)
    return fake
