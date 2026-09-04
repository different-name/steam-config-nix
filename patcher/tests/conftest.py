import pytest


class FakeSteam:
    def __init__(self):
        self.running = False
        self.game_running = False
        self.close_calls = 0
        self.wait_calls = 0
        self.game_wait_calls = 0
        self.on_close = None
        self.on_wait = None

    def is_running(self):
        return self.running

    def is_game_running(self):
        return self.game_running

    def close(self):
        self.close_calls += 1
        self.running = False
        if self.on_close is not None:
            self.on_close()

    def wait(self):
        self.wait_calls += 1
        self.running = False
        if self.on_wait is not None:
            self.on_wait()

    def wait_for_game(self):
        self.game_wait_calls += 1
        self.game_running = False


@pytest.fixture
def fake_steam(monkeypatch):
    fake = FakeSteam()
    monkeypatch.setattr("steam_config_patcher.patcher.steam_is_running", fake.is_running)
    monkeypatch.setattr("steam_config_patcher.patcher.game_is_running", fake.is_game_running)
    monkeypatch.setattr("steam_config_patcher.patcher.close_steam", fake.close)
    monkeypatch.setattr("steam_config_patcher.patcher.wait_for_steam_exit", fake.wait)
    monkeypatch.setattr("steam_config_patcher.patcher.wait_for_game_exit", fake.wait_for_game)
    return fake
