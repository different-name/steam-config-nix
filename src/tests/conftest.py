import pytest


class FakeSteam:
    def __init__(self):
        self.running = False
        self.calls = []

    def steam_is_closed(self, close_if_running=False):
        self.calls.append(close_if_running)
        if not self.running:
            return True
        if close_if_running:
            self.running = False
            return True
        return False


@pytest.fixture
def fake_steam(monkeypatch):
    fake = FakeSteam()
    for module in (
        "steam_config_patcher.formats.keyvalues",
        "steam_config_patcher.formats.binary_keyvalues",
    ):
        monkeypatch.setattr(f"{module}.steam_is_closed", fake.steam_is_closed)
    return fake
