from typing import Optional, Callable

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
        shutdown_behavior=cfg.shutdown_behavior,
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
        shutdown_behavior=cfg.shutdown_behavior,
    )


def patch_config_files(cfg: PatcherConfig):
    config_patches = [
        generate_config_vdf_patch(cfg),
        *[
            generate_localconfig_vdf_patch(cfg, user_id, user)
            for user_id, user in cfg.users.items()
        ],
    ]

    restart_steam: Optional[Callable] = None

    for config_patch in config_patches:
        match config_patch.file_format:
            case "keyvalues":
                value = patch_keyvalues(config_patch)
                if restart_steam == None:
                    restart_steam = value

    if restart_steam != None:
        restart_steam(cfg.restart_cmdline)
