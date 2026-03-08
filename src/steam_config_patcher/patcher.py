import vdf

from steam_config_patcher.formats.binary_keyvalues import patch_binary_keyvalues
from steam_config_patcher.formats.keyvalues import patch_keyvalues
from steam_config_patcher.types import ConfigPatch, PatcherConfig, UserConfig


def generate_config_vdf_patch(cfg: PatcherConfig) -> ConfigPatch:
    return ConfigPatch(
        file_path=cfg.steam_dir.joinpath("config", "config.vdf"),
        file_format="keyvalues",
        data={
            "InstallConfigStore": {
                "Software": {
                    "Valve": {
                        "Steam": {
                            "CompatToolMapping": {
                                str(app_id): {
                                    "config": "",
                                    "name": compat_tool.name,
                                    "priority": str(compat_tool.priority),
                                }
                                for app_id, compat_tool in cfg.compat_tool_mapping.items()
                            }
                        }
                    }
                }
            }
        },
        close_steam=cfg.close_steam,
    )


def generate_localconfig_vdf_patch(
    cfg: PatcherConfig, user_id: int, user_config: UserConfig
) -> ConfigPatch:
    return ConfigPatch(
        file_path=cfg.steam_dir.joinpath(
            "userdata", str(user_id), "config", "localconfig.vdf"
        ),
        file_format="keyvalues",
        data={
            "UserLocalConfigStore": {
                "Software": {
                    "Valve": {
                        "Steam": {
                            "Apps": {
                                str(app_id): {"LaunchOptions": launch_options}
                                for app_id, launch_options in user_config.launch_options.items()
                            }
                        }
                    }
                }
            }
        },
        close_steam=cfg.close_steam,
    )


def generate_shortcuts_vdf_patch(
    cfg: PatcherConfig, user_id: int, user_config: UserConfig
) -> ConfigPatch:
    file_path = cfg.steam_dir.joinpath(
        "userdata", str(user_id), "config", "shortcuts.vdf"
    )

    # hacky way to skip patching, non existant file_path will be skipped in patching stage
    if not file_path.is_file():
        return ConfigPatch(
            file_path=file_path,
            file_format="binary-keyvalues",
            data={},
            close_steam=cfg.close_steam,
        )

    with file_path.open(mode="rb") as read_file:
        kv = vdf.binary_load(read_file)

    # hacky way to see which index we should use based on app id and existing shortcuts
    shortcuts = kv.get("shortcuts") or {}
    index_mapping: dict[int, int] = {}
    max_index = max([int(k) for k in shortcuts.keys()])
    index_offset = 1

    for app_id in user_config.non_steam_apps.keys():
        # set index by matching app id
        for shortcut_index, shortcut in shortcuts.items():
            if shortcut.get("appid") == app_id:
                index_mapping[app_id] = shortcut_index
                break

        # if no matching app id, use next available index
        if app_id not in index_mapping:
            index_mapping[app_id] = max_index + index_offset
            index_offset += 1

    return ConfigPatch(
        file_path=file_path,
        file_format="binary-keyvalues",
        data={
            "shortcuts": {
                str(index_mapping[app_id]): {
                    "appid": app_id,
                    "AppName": app.name,
                    "Exe": app.target,
                    "StartDir": app.start_in,
                    "icon": app.icon,
                    "LaunchOptions": app.launch_options,
                    "IsHidden": 1 if app.is_hidden else 0,
                    "AllowDesktopConfig": 1 if app.allow_desktop_config else 0,
                    "OpenVR": 1 if app.in_vr_library else 0,
                    "tags": {},
                }
                for app_id, app in user_config.non_steam_apps.items()
            }
        },
        close_steam=cfg.close_steam,
    )


def patch_config_files(cfg: PatcherConfig):
    config_patches = [
        generate_config_vdf_patch(cfg),
        *[
            generate_localconfig_vdf_patch(cfg, user_id, user)
            for user_id, user in cfg.users.items()
        ],
        *[
            generate_shortcuts_vdf_patch(cfg, user_id, user)
            for user_id, user in cfg.users.items()
        ],
    ]

    for config_patch in config_patches:
        match config_patch.file_format:
            case "keyvalues":
                patch_keyvalues(config_patch)
            case "binary-keyvalues":
                patch_binary_keyvalues(config_patch)
