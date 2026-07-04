import json

import pytest
from pydantic import ValidationError

from steam_config_patcher.main import parse_input
from steam_config_patcher.types import NonSteamAppConfig

USER_IDS = (111, 222)


def base_input(**overrides):
    data = {
        "onSteamRunning": "wait",
        "defaultCompatTool": None,
        "apps": {},
        "nonSteamApps": {},
    }
    data.update(overrides)
    return data


def non_steam_app_input(**overrides):
    data = {
        "id": 2434605777,
        "name": "Game",
        "target": "/games/game/start",
        "startIn": None,
        "icon": None,
        "isHidden": False,
        "allowOverlay": True,
        "inVrLibrary": False,
    }
    data.update(overrides)
    return data


def run_parse(tmp_path, monkeypatch, data):
    steam_dir = tmp_path / "steam"
    for user_id in USER_IDS:
        (steam_dir / "userdata" / str(user_id)).mkdir(parents=True)
    cfg_path = tmp_path / "cfg.json"
    cfg_path.write_text(json.dumps(data), encoding="utf-8")
    monkeypatch.setattr(
        "steam_config_patcher.main.get_steam_dir", lambda: steam_dir
    )
    monkeypatch.setattr("sys.argv", ["steam-config-patcher", str(cfg_path)])
    return parse_input()


def test_apps_translate_to_launch_options_and_compat_tools(tmp_path, monkeypatch):
    data = base_input(
        apps={
            "cyberpunk": {
                "id": 1091500,
                "launchOptions": "wrapper %command%",
                "compatTool": "GE-Proton",
            }
        }
    )

    cfg = run_parse(tmp_path, monkeypatch, data)

    assert cfg.compat_tool_mapping[1091500].name == "GE-Proton"
    assert cfg.compat_tool_mapping[1091500].priority == 250
    assert sorted(cfg.users) == sorted(USER_IDS)
    for user in cfg.users.values():
        assert user.launch_options == {1091500: "wrapper %command%"}


def test_default_compat_tool_maps_to_id_zero_with_low_priority(tmp_path, monkeypatch):
    data = base_input(defaultCompatTool="GE-Proton")

    cfg = run_parse(tmp_path, monkeypatch, data)

    assert cfg.compat_tool_mapping[0].name == "GE-Proton"
    assert cfg.compat_tool_mapping[0].priority == 75


def test_no_default_compat_tool_omits_id_zero(tmp_path, monkeypatch):
    cfg = run_parse(tmp_path, monkeypatch, base_input())

    assert cfg.compat_tool_mapping == {}


def test_apps_without_options_are_excluded(tmp_path, monkeypatch):
    data = base_input(apps={"portal": {"id": 620}})

    cfg = run_parse(tmp_path, monkeypatch, data)

    assert cfg.compat_tool_mapping == {}
    for user in cfg.users.values():
        assert user.launch_options == {}


def test_non_steam_app_fills_defaults(tmp_path, monkeypatch):
    data = base_input(nonSteamApps={"game": non_steam_app_input()})

    cfg = run_parse(tmp_path, monkeypatch, data)

    for user in cfg.users.values():
        assert user.non_steam_apps == {
            2434605777: NonSteamAppConfig(
                name="Game",
                target="/games/game/start",
                start_in="",
                icon="",
                launch_options="",
                is_hidden=False,
                allow_desktop_config=True,
                allow_overlay=True,
                in_vr_library=False,
            )
        }


def test_non_steam_app_compat_tool_is_mapped(tmp_path, monkeypatch):
    data = base_input(
        nonSteamApps={"game": non_steam_app_input(compatTool="proton_experimental")}
    )

    cfg = run_parse(tmp_path, monkeypatch, data)

    assert cfg.compat_tool_mapping[2434605777].name == "proton_experimental"
    assert cfg.compat_tool_mapping[2434605777].priority == 250


def test_beta_branches_map_to_game_betas(tmp_path, monkeypatch):
    data = base_input(
        apps={
            "cyberpunk": {"id": 1091500, "betaBranch": "prerelease"},
            "portal": {"id": 620},
        }
    )

    cfg = run_parse(tmp_path, monkeypatch, data)

    assert cfg.game_betas == {1091500: "prerelease"}


def test_languages_map_to_game_languages(tmp_path, monkeypatch):
    data = base_input(
        apps={
            "cyberpunk": {"id": 1091500, "language": "german"},
            "portal": {"id": 620},
        }
    )

    cfg = run_parse(tmp_path, monkeypatch, data)

    assert cfg.game_languages == {1091500: "german"}


def test_update_behavior_maps_to_game_update_behaviors(tmp_path, monkeypatch):
    data = base_input(
        apps={
            "cyberpunk": {"id": 1091500, "updateBehavior": "1"},
            "portal": {"id": 620},
        }
    )

    cfg = run_parse(tmp_path, monkeypatch, data)

    assert cfg.game_update_behaviors == {1091500: "1"}


def test_artwork_maps_to_grid_art_for_both_app_types(tmp_path, monkeypatch):
    data = base_input(
        apps={"cyberpunk": {"id": 1091500, "artwork": {"hero": "/art/hero.jpg"}}},
        nonSteamApps={
            "game": non_steam_app_input(artwork={"cover": "/art/cover.jpg"})
        },
    )

    cfg = run_parse(tmp_path, monkeypatch, data)

    assert cfg.grid_art[1091500].hero == "/art/hero.jpg"
    assert cfg.grid_art[2434605777].cover == "/art/cover.jpg"


def test_apps_without_artwork_are_excluded_from_grid_art(tmp_path, monkeypatch):
    data = base_input(apps={"portal": {"id": 620}})

    cfg = run_parse(tmp_path, monkeypatch, data)

    assert cfg.grid_art == {}


def test_strategy_and_steam_dir_are_passed_through(tmp_path, monkeypatch):
    cfg = run_parse(tmp_path, monkeypatch, base_input(onSteamRunning="close"))

    assert cfg.on_steam_running == "close"
    assert cfg.steam_dir == tmp_path / "steam"


def test_unknown_strategy_raises(tmp_path, monkeypatch):
    with pytest.raises(ValidationError):
        run_parse(tmp_path, monkeypatch, base_input(onSteamRunning="sometimes"))


def make_tool_dir(tmp_path, name):
    tool_dir = tmp_path / f"tool-{name}"
    tool_dir.mkdir()
    (tool_dir / "compatibilitytool.vdf").write_text(
        f'"compatibilitytools"\n{{\n\t"compat_tools"\n\t{{\n\t\t"{name}"\n\t\t{{\n'
        '\t\t\t"install_path"\t\t"."\n\t\t}\n\t}\n}\n',
        encoding="utf-8",
    )
    return tool_dir


def test_compat_tool_package_ref_is_resolved(tmp_path, monkeypatch):
    tool_dir = make_tool_dir(tmp_path, "GE-Proton")
    data = base_input(
        apps={"cyberpunk": {"id": 1091500, "compatTool": {"path": str(tool_dir)}}}
    )

    cfg = run_parse(tmp_path, monkeypatch, data)

    assert cfg.compat_tool_mapping[1091500].name == "GE-Proton"


def test_default_compat_tool_package_ref_is_resolved(tmp_path, monkeypatch):
    tool_dir = make_tool_dir(tmp_path, "Custom-Proton")
    data = base_input(defaultCompatTool={"path": str(tool_dir)})

    cfg = run_parse(tmp_path, monkeypatch, data)

    assert cfg.compat_tool_mapping[0].name == "Custom-Proton"
    assert cfg.compat_tool_mapping[0].priority == 75


def test_missing_required_field_raises(tmp_path, monkeypatch):
    data = base_input(apps={"portal": {"launchOptions": "-vulkan"}})

    with pytest.raises(ValidationError):
        run_parse(tmp_path, monkeypatch, data)


def test_unknown_app_field_raises(tmp_path, monkeypatch):
    # guards against the module's finalConfig drifting from this schema
    data = base_input(apps={"portal": {"id": 620, "somethingNew": "x"}})

    with pytest.raises(ValidationError):
        run_parse(tmp_path, monkeypatch, data)


def test_unknown_top_level_field_raises(tmp_path, monkeypatch):
    data = base_input(unexpected=True)

    with pytest.raises(ValidationError):
        run_parse(tmp_path, monkeypatch, data)
