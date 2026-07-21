import json

import pytest

from steam_config_patcher.files_manifest import load_files_manifest
from steam_config_patcher.manifest import load_manifest, manifest_path
from steam_config_patcher.patcher import (
    desired_manifest,
    generate_config_vdf_patch,
    generate_shortcuts_vdf_patch,
    patch_config_files,
)
from steam_config_patcher.types import (
    CompatToolConfig,
    FileOp,
    GridArt,
    ManagedKey,
    NonSteamAppConfig,
    PatcherConfig,
    UserConfig,
    UserManifest,
)
from steam_config_patcher.vdf import binary, text

USER_ID = 111

CONFIG_VDF = """\
"InstallConfigStore"
{
	"Software"
	{
		"Valve"
		{
			"Steam"
			{
				"CompatToolMapping"
				{
				}
			}
		}
	}
}
"""

LOCALCONFIG_VDF = """\
"UserLocalConfigStore"
{
	"Software"
	{
		"Valve"
		{
			"Steam"
			{
				"Apps"
				{
				}
			}
		}
	}
}
"""

MAPPING_PATH = ("InstallConfigStore", "Software", "Valve", "Steam", "CompatToolMapping")
APPS_PATH = ("UserLocalConfigStore", "Software", "Valve", "Steam", "Apps")


def make_steam_dir(tmp_path):
    steam_dir = tmp_path / "steam"
    (steam_dir / "config").mkdir(parents=True)
    (steam_dir / "config" / "config.vdf").write_text(CONFIG_VDF, encoding="utf-8")
    user_config = steam_dir / "userdata" / str(USER_ID) / "config"
    user_config.mkdir(parents=True)
    (user_config / "localconfig.vdf").write_text(LOCALCONFIG_VDF, encoding="utf-8")
    (user_config / "shortcuts.vdf").write_bytes(binary.dumps({"shortcuts": {}}))
    (steam_dir / "steamapps").mkdir()
    return steam_dir


APPMANIFEST_VDF = """\
"AppState"
{
	"appid"		"1091500"
	"name"		"Cyberpunk 2077"
	"StateFlags"		"4"
	"UserConfig"
	{
		"language"		"english"
	}
}
"""

BETA_KEY_PATH = ("AppState", "UserConfig", "BetaKey")
LANGUAGE_KEY_PATH = ("AppState", "UserConfig", "language")
AUTO_UPDATE_KEY_PATH = ("AppState", "AutoUpdateBehavior")


def write_app_manifest(steam_dir, app_id=1091500):
    path = steam_dir / "steamapps" / f"appmanifest_{app_id}.acf"
    path.write_text(APPMANIFEST_VDF, encoding="utf-8")
    return path


def make_cfg(
    steam_dir,
    on_steam_running="wait",
    compat_tool_mapping=None,
    launch_options=None,
    non_steam_apps=None,
    game_betas=None,
    game_languages=None,
    game_update_behaviors=None,
    grid_art=None,
    file_ops=None,
    remove_ops=None,
):
    return PatcherConfig(
        on_steam_running=on_steam_running,
        steam_dir=steam_dir,
        game_betas=game_betas or {},
        game_languages=game_languages or {},
        game_update_behaviors=game_update_behaviors or {},
        grid_art=grid_art or {},
        compat_tool_mapping=compat_tool_mapping or {},
        file_ops=file_ops or [],
        remove_ops=remove_ops or [],
        users={
            USER_ID: UserConfig(
                launch_options=launch_options or {},
                non_steam_apps=non_steam_apps or {},
            )
        },
    )


def non_steam_app(name="Game", target="/games/some game/start", start_in="", icon=""):
    return NonSteamAppConfig(
        name=name,
        target=target,
        start_in=start_in,
        icon=icon,
        launch_options="",
        is_hidden=False,
        allow_desktop_config=True,
        allow_overlay=True,
        in_vr_library=False,
    )


def find_values(path, key_path):
    root = text.loads(path.read_text(encoding="utf-8"))
    return [node.value for node in root.find_all(*key_path)]


def read_shortcuts(steam_dir):
    path = steam_dir / "userdata" / str(USER_ID) / "config" / "shortcuts.vdf"
    return binary.loads(path.read_bytes())


def test_config_vdf_patch_data_and_priorities(tmp_path):
    steam_dir = make_steam_dir(tmp_path)
    cfg = make_cfg(
        steam_dir,
        compat_tool_mapping={
            0: CompatToolConfig("proton_experimental", 75),
            1091500: CompatToolConfig("GE-Proton", 250),
        },
    )

    patch = generate_config_vdf_patch(cfg, prev_keys=[])

    mapping = patch.data["InstallConfigStore"]["Software"]["Valve"]["Steam"][
        "CompatToolMapping"
    ]
    assert mapping["0"] == {"config": "", "name": "proton_experimental", "priority": "75"}
    assert mapping["1091500"] == {"config": "", "name": "GE-Proton", "priority": "250"}
    assert patch.deletions == []


def compat_key(app_id, name):
    return ManagedKey(
        file="config",
        key_path=MAPPING_PATH + (str(app_id),),
        guard_path=("name",),
        expected=name,
    )


def test_config_vdf_patch_deletes_removed_guarded_by_name(tmp_path):
    steam_dir = make_steam_dir(tmp_path)
    cfg = make_cfg(steam_dir, compat_tool_mapping={620: CompatToolConfig("GE-Proton", 250)})

    patch = generate_config_vdf_patch(
        cfg,
        prev_keys=[
            compat_key(620, "GE-Proton"),
            compat_key(999, "old-tool"),
            compat_key(555, "other-tool"),
        ],
    )

    assert [(d.key_path[-1], d.guard_path, d.expected) for d in patch.deletions] == [
        ("555", ("name",), "other-tool"),
        ("999", ("name",), "old-tool"),
    ]


def test_config_vdf_patch_dedupes_prev_keys_across_users(tmp_path):
    steam_dir = make_steam_dir(tmp_path)
    cfg = make_cfg(steam_dir)

    patch = generate_config_vdf_patch(
        cfg,
        prev_keys=[compat_key(999, "old-tool"), compat_key(999, "old-tool")],
    )

    assert len(patch.deletions) == 1


def test_shortcuts_patch_reuses_index_for_existing_appid(fake_steam, tmp_path):
    steam_dir = make_steam_dir(tmp_path)
    path = steam_dir / "userdata" / str(USER_ID) / "config" / "shortcuts.vdf"
    path.write_bytes(
        binary.dumps({"shortcuts": {"0": {"appid": 555}, "1": {"appid": 777}}})
    )
    cfg = make_cfg(
        steam_dir,
        non_steam_apps={777: non_steam_app(name="Old"), 888: non_steam_app(name="New")},
    )

    patch = generate_shortcuts_vdf_patch(cfg, USER_ID, cfg.users[USER_ID], UserManifest())

    assert patch.data["shortcuts"]["1"]["appid"] == 777
    assert patch.data["shortcuts"]["2"]["appid"] == 888


def test_shortcuts_patch_quotes_exe_and_start_dir(fake_steam, tmp_path):
    steam_dir = make_steam_dir(tmp_path)
    cfg = make_cfg(
        steam_dir,
        non_steam_apps={
            555: non_steam_app(target="/games/some game/start", start_in="/games/some game")
        },
    )

    patch = generate_shortcuts_vdf_patch(cfg, USER_ID, cfg.users[USER_ID], UserManifest())

    shortcut = patch.data["shortcuts"]["0"]
    assert shortcut["Exe"] == '"/games/some game/start"'
    assert shortcut["StartDir"] == '"/games/some game"'


def test_shortcuts_patch_leaves_empty_start_dir_unquoted(fake_steam, tmp_path):
    steam_dir = make_steam_dir(tmp_path)
    cfg = make_cfg(steam_dir, non_steam_apps={555: non_steam_app(start_in="")})

    patch = generate_shortcuts_vdf_patch(cfg, USER_ID, cfg.users[USER_ID], UserManifest())

    assert patch.data["shortcuts"]["0"]["StartDir"] == ""


def test_shortcuts_patch_deletes_removed_appids(fake_steam, tmp_path):
    steam_dir = make_steam_dir(tmp_path)
    path = steam_dir / "userdata" / str(USER_ID) / "config" / "shortcuts.vdf"
    path.write_bytes(
        binary.dumps({"shortcuts": {"0": {"appid": 555}, "1": {"appid": 777}}})
    )
    cfg = make_cfg(steam_dir)

    patch = generate_shortcuts_vdf_patch(
        cfg, USER_ID, cfg.users[USER_ID], UserManifest(shortcuts=[555])
    )

    assert [d.key_path for d in patch.deletions] == [("shortcuts", "0")]


def test_shortcuts_patch_missing_file_creates_shortcut(fake_steam, tmp_path):
    steam_dir = make_steam_dir(tmp_path)
    (steam_dir / "userdata" / str(USER_ID) / "config" / "shortcuts.vdf").unlink()
    cfg = make_cfg(steam_dir, non_steam_apps={555: non_steam_app()})

    patch = generate_shortcuts_vdf_patch(cfg, USER_ID, cfg.users[USER_ID], UserManifest())

    assert patch.data["shortcuts"]["0"]["appid"] == 555
    assert patch.deletions == []


def test_shortcuts_patch_missing_file_no_apps_is_empty(fake_steam, tmp_path):
    steam_dir = make_steam_dir(tmp_path)
    (steam_dir / "userdata" / str(USER_ID) / "config" / "shortcuts.vdf").unlink()
    cfg = make_cfg(steam_dir)

    patch = generate_shortcuts_vdf_patch(cfg, USER_ID, cfg.users[USER_ID], UserManifest())

    assert patch.data == {}
    assert patch.deletions == []


def test_desired_manifest_reflects_config(tmp_path):
    steam_dir = make_steam_dir(tmp_path)
    cfg = make_cfg(
        steam_dir,
        compat_tool_mapping={620: CompatToolConfig("GE-Proton", 250)},
        launch_options={620: "wrapper %command%"},
        non_steam_apps={555: non_steam_app()},
    )

    manifest = desired_manifest(cfg, cfg.users[USER_ID])

    assert manifest == UserManifest(
        managed_keys=[
            compat_key(620, "GE-Proton"),
            ManagedKey(
                file="localconfig",
                key_path=APPS_PATH + ("620", "LaunchOptions"),
                expected="wrapper %command%",
            ),
        ],
        shortcuts=[555],
    )


def test_full_run_patches_files_and_writes_manifest(fake_steam, tmp_path):
    steam_dir = make_steam_dir(tmp_path)
    cfg = make_cfg(
        steam_dir,
        compat_tool_mapping={1091500: CompatToolConfig("GE-Proton", 250)},
        launch_options={620: "wrapper %command%"},
        non_steam_apps={555: non_steam_app(name="Game")},
    )

    patch_config_files(cfg)

    config_vdf = steam_dir / "config" / "config.vdf"
    localconfig_vdf = steam_dir / "userdata" / str(USER_ID) / "config" / "localconfig.vdf"
    assert find_values(config_vdf, MAPPING_PATH + ("1091500", "name")) == ["GE-Proton"]
    assert find_values(localconfig_vdf, APPS_PATH + ("620", "LaunchOptions")) == [
        "wrapper %command%"
    ]
    assert read_shortcuts(steam_dir)["shortcuts"]["0"]["AppName"] == "Game"
    assert load_manifest(steam_dir, USER_ID) == desired_manifest(cfg, cfg.users[USER_ID])


def test_full_run_creates_shortcuts_file_when_missing(fake_steam, tmp_path):
    steam_dir = make_steam_dir(tmp_path)
    shortcuts_path = steam_dir / "userdata" / str(USER_ID) / "config" / "shortcuts.vdf"
    shortcuts_path.unlink()
    cfg = make_cfg(steam_dir, non_steam_apps={555: non_steam_app(name="Game")})

    patch_config_files(cfg)

    assert read_shortcuts(steam_dir)["shortcuts"]["0"]["AppName"] == "Game"


def install_dir_for(steam_dir, app_id=620, name="Portal 2"):
    manifest = steam_dir / "steamapps" / f"appmanifest_{app_id}.acf"
    manifest.write_text(
        f'"AppState"\n{{\n\t"appid"\t\t"{app_id}"\n'
        f'\t"installdir"\t\t"{name}"\n}}\n',
        encoding="utf-8",
    )
    install = steam_dir / "steamapps" / "common" / name
    install.mkdir(parents=True)
    return install


def test_full_run_applies_file_ops(fake_steam, tmp_path):
    steam_dir = make_steam_dir(tmp_path)
    install = install_dir_for(steam_dir)
    source = tmp_path / "mod.dll"
    source.write_text("mod")
    cfg = make_cfg(
        steam_dir,
        file_ops=[
            FileOp(
                app_id=620,
                location="install",
                target="Mods/mod.dll",
                source=source,
                overwrite_changes=True,
            )
        ],
    )

    patch_config_files(cfg)

    assert (install / "Mods" / "mod.dll").read_text() == "mod"
    assert len(load_files_manifest(steam_dir).files) == 1


def test_file_ops_reverted_on_next_run(fake_steam, tmp_path):
    steam_dir = make_steam_dir(tmp_path)
    install = install_dir_for(steam_dir)
    source = tmp_path / "mod.dll"
    source.write_text("mod")
    file_op = FileOp(
        app_id=620,
        location="install",
        target="Mods/mod.dll",
        source=source,
        overwrite_changes=True,
    )

    patch_config_files(make_cfg(steam_dir, file_ops=[file_op]))
    patch_config_files(make_cfg(steam_dir))

    assert not (install / "Mods").exists()
    assert load_files_manifest(steam_dir).files == []


def test_second_run_cleans_up_removed_entries(fake_steam, tmp_path):
    steam_dir = make_steam_dir(tmp_path)
    cfg = make_cfg(
        steam_dir,
        compat_tool_mapping={1091500: CompatToolConfig("GE-Proton", 250)},
        launch_options={620: "wrapper %command%"},
        non_steam_apps={555: non_steam_app()},
    )
    patch_config_files(cfg)

    patch_config_files(make_cfg(steam_dir))

    config_vdf = steam_dir / "config" / "config.vdf"
    localconfig_vdf = steam_dir / "userdata" / str(USER_ID) / "config" / "localconfig.vdf"
    assert find_values(config_vdf, MAPPING_PATH + ("1091500",)) == []
    assert find_values(localconfig_vdf, APPS_PATH + ("620", "LaunchOptions")) == []
    assert read_shortcuts(steam_dir)["shortcuts"] == {}
    assert load_manifest(steam_dir, USER_ID) == UserManifest()


def test_v1_manifest_entries_are_cleaned_up(fake_steam, tmp_path):
    steam_dir = make_steam_dir(tmp_path)
    cfg = make_cfg(
        steam_dir,
        compat_tool_mapping={1091500: CompatToolConfig("GE-Proton", 250)},
        launch_options={620: "wrapper %command%"},
    )
    patch_config_files(cfg)

    manifest_path(steam_dir, USER_ID).write_text(
        json.dumps(
            {
                "version": 1,
                "compat_tools": {"1091500": "GE-Proton"},
                "launch_options": {"620": "wrapper %command%"},
                "shortcuts": [],
            }
        ),
        encoding="utf-8",
    )

    patch_config_files(make_cfg(steam_dir))

    config_vdf = steam_dir / "config" / "config.vdf"
    localconfig_vdf = steam_dir / "userdata" / str(USER_ID) / "config" / "localconfig.vdf"
    assert find_values(config_vdf, MAPPING_PATH + ("1091500",)) == []
    assert find_values(localconfig_vdf, APPS_PATH + ("620", "LaunchOptions")) == []


def test_beta_branch_written_and_cleaned_up(fake_steam, tmp_path):
    steam_dir = make_steam_dir(tmp_path)
    manifest = write_app_manifest(steam_dir)

    patch_config_files(make_cfg(steam_dir, game_betas={1091500: "prerelease"}))

    assert find_values(manifest, BETA_KEY_PATH) == ["prerelease"]
    assert find_values(manifest, ("AppState", "UserConfig", "language")) == ["english"]

    patch_config_files(make_cfg(steam_dir))

    assert find_values(manifest, BETA_KEY_PATH) == []
    assert load_manifest(steam_dir, USER_ID) == UserManifest()


def test_beta_branch_changed_by_user_is_kept(fake_steam, tmp_path):
    steam_dir = make_steam_dir(tmp_path)
    manifest = write_app_manifest(steam_dir)
    patch_config_files(make_cfg(steam_dir, game_betas={1091500: "prerelease"}))

    manifest.write_text(
        manifest.read_text(encoding="utf-8").replace("prerelease", "userbeta"),
        encoding="utf-8",
    )
    patch_config_files(make_cfg(steam_dir))

    assert find_values(manifest, BETA_KEY_PATH) == ["userbeta"]


def test_beta_branch_for_uninstalled_app_warns_and_continues(fake_steam, tmp_path):
    steam_dir = make_steam_dir(tmp_path)

    patch_config_files(make_cfg(steam_dir, game_betas={1091500: "prerelease"}))

    assert manifest_path(steam_dir, USER_ID).exists()


def test_language_written_and_cleaned_up(fake_steam, tmp_path):
    steam_dir = make_steam_dir(tmp_path)
    manifest = write_app_manifest(steam_dir)

    patch_config_files(make_cfg(steam_dir, game_languages={1091500: "german"}))

    assert find_values(manifest, LANGUAGE_KEY_PATH) == ["german"]

    patch_config_files(make_cfg(steam_dir))

    assert find_values(manifest, LANGUAGE_KEY_PATH) == []
    assert load_manifest(steam_dir, USER_ID) == UserManifest()


def test_update_behavior_written_and_cleaned_up(fake_steam, tmp_path):
    steam_dir = make_steam_dir(tmp_path)
    manifest = write_app_manifest(steam_dir)

    patch_config_files(make_cfg(steam_dir, game_update_behaviors={1091500: "1"}))

    assert find_values(manifest, AUTO_UPDATE_KEY_PATH) == ["1"]

    patch_config_files(make_cfg(steam_dir))

    assert find_values(manifest, AUTO_UPDATE_KEY_PATH) == []
    assert load_manifest(steam_dir, USER_ID) == UserManifest()


def test_beta_and_language_share_one_appmanifest_patch(fake_steam, tmp_path):
    steam_dir = make_steam_dir(tmp_path)
    manifest = write_app_manifest(steam_dir)

    patch_config_files(
        make_cfg(
            steam_dir,
            game_betas={1091500: "prerelease"},
            game_languages={1091500: "german"},
        )
    )

    assert find_values(manifest, BETA_KEY_PATH) == ["prerelease"]
    assert find_values(manifest, LANGUAGE_KEY_PATH) == ["german"]


def test_language_for_uninstalled_app_warns_and_continues(fake_steam, tmp_path):
    steam_dir = make_steam_dir(tmp_path)

    patch_config_files(make_cfg(steam_dir, game_languages={1091500: "german"}))

    assert manifest_path(steam_dir, USER_ID).exists()


def test_grid_art_applied_and_cleaned_up(fake_steam, tmp_path):
    steam_dir = make_steam_dir(tmp_path)
    art = tmp_path / "hero.jpg"
    art.write_bytes(b"image")
    grid_dir = steam_dir / "userdata" / str(USER_ID) / "config" / "grid"

    patch_config_files(make_cfg(steam_dir, grid_art={438100: GridArt(hero=str(art))}))

    link = grid_dir / "438100_hero.jpg"
    assert link.is_symlink()
    assert load_manifest(steam_dir, USER_ID).grid_art == {"438100_hero.jpg": str(art)}

    patch_config_files(make_cfg(steam_dir))

    assert not link.exists()
    assert load_manifest(steam_dir, USER_ID).grid_art == {}


def test_cleanup_keeps_values_changed_by_user(fake_steam, tmp_path):
    steam_dir = make_steam_dir(tmp_path)
    cfg = make_cfg(
        steam_dir,
        compat_tool_mapping={1091500: CompatToolConfig("GE-Proton", 250)},
        launch_options={620: "wrapper %command%"},
    )
    patch_config_files(cfg)

    config_vdf = steam_dir / "config" / "config.vdf"
    localconfig_vdf = steam_dir / "userdata" / str(USER_ID) / "config" / "localconfig.vdf"
    for path, old, new in [
        (config_vdf, "GE-Proton", "user-tool"),
        (localconfig_vdf, "wrapper %command%", "user options"),
    ]:
        path.write_text(
            path.read_text(encoding="utf-8").replace(old, new), encoding="utf-8"
        )

    patch_config_files(make_cfg(steam_dir))

    assert find_values(config_vdf, MAPPING_PATH + ("1091500", "name")) == ["user-tool"]
    assert find_values(localconfig_vdf, APPS_PATH + ("620", "LaunchOptions")) == [
        "user options"
    ]


def test_skip_strategy_writes_nothing(fake_steam, tmp_path):
    fake_steam.running = True
    steam_dir = make_steam_dir(tmp_path)
    original_config = (steam_dir / "config" / "config.vdf").read_text(encoding="utf-8")
    cfg = make_cfg(
        steam_dir,
        on_steam_running="skip",
        compat_tool_mapping={1091500: CompatToolConfig("GE-Proton", 250)},
        launch_options={620: "wrapper %command%"},
    )

    patch_config_files(cfg)

    assert (steam_dir / "config" / "config.vdf").read_text(encoding="utf-8") == original_config
    assert not manifest_path(steam_dir, USER_ID).exists()
    assert fake_steam.close_calls == 0
    assert fake_steam.wait_calls == 0


def test_file_ops_apply_even_when_steam_running_and_skipping(fake_steam, tmp_path):
    fake_steam.running = True
    steam_dir = make_steam_dir(tmp_path)
    install = install_dir_for(steam_dir)
    original_config = (steam_dir / "config" / "config.vdf").read_text(encoding="utf-8")
    source = tmp_path / "mod.dll"
    source.write_text("mod")
    cfg = make_cfg(
        steam_dir,
        on_steam_running="skip",
        compat_tool_mapping={1091500: CompatToolConfig("GE-Proton", 250)},
        file_ops=[
            FileOp(
                app_id=620,
                location="install",
                target="Mods/mod.dll",
                source=source,
                overwrite_changes=True,
            )
        ],
    )

    patch_config_files(cfg)

    assert (steam_dir / "config" / "config.vdf").read_text(encoding="utf-8") == original_config
    assert (install / "Mods" / "mod.dll").read_text() == "mod"


def test_file_ops_skipped_when_game_running_and_skipping(fake_steam, tmp_path):
    fake_steam.running = True
    fake_steam.game_running = True
    steam_dir = make_steam_dir(tmp_path)
    install = install_dir_for(steam_dir)
    source = tmp_path / "mod.dll"
    source.write_text("mod")
    cfg = make_cfg(
        steam_dir,
        on_steam_running="skip",
        file_ops=[
            FileOp(
                app_id=620,
                location="install",
                target="Mods/mod.dll",
                source=source,
                overwrite_changes=True,
            )
        ],
    )

    patch_config_files(cfg)

    assert not (install / "Mods" / "mod.dll").exists()


def file_op_cfg(steam_dir, **kwargs):
    source = steam_dir.parent / "mod.dll"
    source.write_text("mod")
    return make_cfg(
        steam_dir,
        file_ops=[
            FileOp(
                app_id=620,
                location="install",
                target="Mods/mod.dll",
                source=source,
                overwrite_changes=True,
            )
        ],
        **kwargs,
    )


def test_file_ops_apply_after_closing_for_running_game(fake_steam, tmp_path):
    fake_steam.running = True
    fake_steam.game_running = True
    steam_dir = make_steam_dir(tmp_path)
    install = install_dir_for(steam_dir)
    cfg = file_op_cfg(
        steam_dir,
        on_steam_running="close",
        compat_tool_mapping={1091500: CompatToolConfig("GE-Proton", 250)},
    )

    patch_config_files(cfg)

    assert fake_steam.game_wait_calls == 1
    assert fake_steam.close_calls == 1
    assert (install / "Mods" / "mod.dll").read_text() == "mod"


def test_file_op_only_change_does_not_close_steam(fake_steam, tmp_path):
    fake_steam.running = True
    fake_steam.game_running = True
    steam_dir = make_steam_dir(tmp_path)
    install = install_dir_for(steam_dir)
    cfg = file_op_cfg(steam_dir, on_steam_running="close")

    patch_config_files(cfg)

    assert fake_steam.close_calls == 0
    assert fake_steam.game_wait_calls == 1
    assert (install / "Mods" / "mod.dll").read_text() == "mod"


def test_force_close_file_op_only_applies_without_waiting_or_closing(fake_steam, tmp_path):
    fake_steam.running = True
    fake_steam.game_running = True
    steam_dir = make_steam_dir(tmp_path)
    install = install_dir_for(steam_dir)
    cfg = file_op_cfg(steam_dir, on_steam_running="force-close")

    patch_config_files(cfg)

    assert fake_steam.close_calls == 0
    assert fake_steam.game_wait_calls == 0
    assert (install / "Mods" / "mod.dll").read_text() == "mod"


def test_wait_waits_for_game_before_file_ops(fake_steam, tmp_path):
    fake_steam.running = True
    fake_steam.game_running = True
    steam_dir = make_steam_dir(tmp_path)
    install = install_dir_for(steam_dir)
    cfg = file_op_cfg(
        steam_dir,
        on_steam_running="wait",
        compat_tool_mapping={1091500: CompatToolConfig("GE-Proton", 250)},
    )

    patch_config_files(cfg)

    assert fake_steam.wait_calls == 1
    assert fake_steam.game_wait_calls == 1
    assert (install / "Mods" / "mod.dll").read_text() == "mod"


def test_vdf_write_failure_does_not_block_file_ops(fake_steam, tmp_path, monkeypatch):
    steam_dir = make_steam_dir(tmp_path)
    install = install_dir_for(steam_dir)
    cfg = file_op_cfg(
        steam_dir,
        compat_tool_mapping={1091500: CompatToolConfig("GE-Proton", 250)},
    )

    def boom(*args, **kwargs):
        raise OSError("disk full")

    monkeypatch.setattr("steam_config_patcher.patcher.atomic_write_bytes", boom)

    with pytest.raises(SystemExit):
        patch_config_files(cfg)

    assert (install / "Mods" / "mod.dll").read_text() == "mod"


def test_wait_strategy_waits_for_steam_exit(fake_steam, tmp_path):
    fake_steam.running = True
    steam_dir = make_steam_dir(tmp_path)
    cfg = make_cfg(
        steam_dir,
        compat_tool_mapping={1091500: CompatToolConfig("GE-Proton", 250)},
    )

    patch_config_files(cfg)

    assert fake_steam.wait_calls == 1
    assert fake_steam.close_calls == 0
    config_vdf = steam_dir / "config" / "config.vdf"
    assert find_values(config_vdf, MAPPING_PATH + ("1091500", "name")) == ["GE-Proton"]
    assert manifest_path(steam_dir, USER_ID).exists()


def test_close_with_game_running_waits_for_game_first(fake_steam, tmp_path):
    fake_steam.running = True
    fake_steam.game_running = True
    steam_dir = make_steam_dir(tmp_path)
    cfg = make_cfg(
        steam_dir,
        on_steam_running="close",
        compat_tool_mapping={1091500: CompatToolConfig("GE-Proton", 250)},
    )

    patch_config_files(cfg)

    assert fake_steam.game_wait_calls == 1
    assert fake_steam.close_calls == 1
    assert fake_steam.wait_calls == 0
    config_vdf = steam_dir / "config" / "config.vdf"
    assert find_values(config_vdf, MAPPING_PATH + ("1091500", "name")) == ["GE-Proton"]


def test_force_close_ignores_running_game(fake_steam, tmp_path):
    fake_steam.running = True
    fake_steam.game_running = True
    steam_dir = make_steam_dir(tmp_path)
    cfg = make_cfg(
        steam_dir,
        on_steam_running="force-close",
        compat_tool_mapping={1091500: CompatToolConfig("GE-Proton", 250)},
    )

    patch_config_files(cfg)

    assert fake_steam.game_wait_calls == 0
    assert fake_steam.close_calls == 1
    config_vdf = steam_dir / "config" / "config.vdf"
    assert find_values(config_vdf, MAPPING_PATH + ("1091500", "name")) == ["GE-Proton"]


def test_close_steam_shuts_down_and_writes(fake_steam, tmp_path):
    fake_steam.running = True
    steam_dir = make_steam_dir(tmp_path)
    cfg = make_cfg(
        steam_dir,
        on_steam_running="close",
        compat_tool_mapping={1091500: CompatToolConfig("GE-Proton", 250)},
    )

    patch_config_files(cfg)

    assert fake_steam.close_calls == 1
    config_vdf = steam_dir / "config" / "config.vdf"
    assert find_values(config_vdf, MAPPING_PATH + ("1091500", "name")) == ["GE-Proton"]
    assert manifest_path(steam_dir, USER_ID).exists()


def test_steam_not_closed_when_nothing_to_change(fake_steam, tmp_path):
    steam_dir = make_steam_dir(tmp_path)
    cfg = make_cfg(
        steam_dir,
        on_steam_running="close",
        compat_tool_mapping={1091500: CompatToolConfig("GE-Proton", 250)},
    )
    patch_config_files(cfg)

    fake_steam.running = True
    patch_config_files(cfg)

    assert fake_steam.close_calls == 0
    assert manifest_path(steam_dir, USER_ID).exists()


def test_files_are_reread_after_closing_steam(fake_steam, tmp_path):
    fake_steam.running = True
    steam_dir = make_steam_dir(tmp_path)
    config_vdf = steam_dir / "config" / "config.vdf"

    def steam_writes_on_exit():
        config_vdf.write_text(
            config_vdf.read_text(encoding="utf-8").replace(
                '"CompatToolMapping"\n\t\t\t\t{\n\t\t\t\t}',
                '"CompatToolMapping"\n\t\t\t\t{\n\t\t\t\t}\n\t\t\t\t"SteamExitWrote"\t\t"1"',
            ),
            encoding="utf-8",
        )

    fake_steam.on_close = steam_writes_on_exit
    cfg = make_cfg(
        steam_dir,
        on_steam_running="close",
        compat_tool_mapping={1091500: CompatToolConfig("GE-Proton", 250)},
    )

    patch_config_files(cfg)

    steam_path = ("InstallConfigStore", "Software", "Valve", "Steam")
    assert find_values(config_vdf, steam_path + ("SteamExitWrote",)) == ["1"]
    assert find_values(config_vdf, MAPPING_PATH + ("1091500", "name")) == ["GE-Proton"]


def test_failing_file_does_not_stop_others(fake_steam, tmp_path):
    steam_dir = make_steam_dir(tmp_path)
    (steam_dir / "config" / "config.vdf").write_text('"broken', encoding="utf-8")
    cfg = make_cfg(
        steam_dir,
        compat_tool_mapping={1091500: CompatToolConfig("GE-Proton", 250)},
        launch_options={620: "wrapper %command%"},
    )

    with pytest.raises(SystemExit):
        patch_config_files(cfg)

    localconfig_vdf = steam_dir / "userdata" / str(USER_ID) / "config" / "localconfig.vdf"
    assert find_values(localconfig_vdf, APPS_PATH + ("620", "LaunchOptions")) == [
        "wrapper %command%"
    ]
