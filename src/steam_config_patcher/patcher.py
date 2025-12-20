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


def patch_config_files(cfg: PatcherConfig):
    config_patches = [
        generate_config_vdf_patch(cfg),
        *[
            generate_localconfig_vdf_patch(cfg, user_id, user)
            for user_id, user in cfg.users.items()
        ],
    ]

    for config_patch in config_patches:
        match config_patch.file_format:
            case "keyvalues":
                patch_keyvalues(config_patch)
