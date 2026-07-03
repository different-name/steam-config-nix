import logging

from steam_config_patcher.formats.binary_keyvalues import patch_binary_keyvalues
from steam_config_patcher.formats.keyvalues import patch_keyvalues
from steam_config_patcher.manifest import load_manifest, save_manifest
from steam_config_patcher.types import (
    ConfigPatch,
    Deletion,
    PatcherConfig,
    UserConfig,
    UserManifest,
)
from steam_config_patcher.vdf import binary

LOG = logging.getLogger(__name__)

LOCALCONFIG_APPS_PATH = ("UserLocalConfigStore", "Software", "Valve", "Steam", "Apps")
COMPAT_TOOL_MAPPING_PATH = (
    "InstallConfigStore",
    "Software",
    "Valve",
    "Steam",
    "CompatToolMapping",
)


def generate_config_vdf_patch(
    cfg: PatcherConfig, prev_compat_tools: dict[int, str]
) -> ConfigPatch:
    # clear compat tool mappings previously set for apps that are no longer configured
    # only if the stored value still matches what we wrote so we don't wipe manual config
    removed_app_ids = set(prev_compat_tools) - set(cfg.compat_tool_mapping)
    deletions = [
        Deletion(
            key_path=COMPAT_TOOL_MAPPING_PATH + (str(app_id),),
            guard_path=("name",),
            expected=prev_compat_tools[app_id],
        )
        for app_id in sorted(removed_app_ids)
    ]

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
        deletions=deletions,
    )


def generate_localconfig_vdf_patch(
    cfg: PatcherConfig,
    user_id: int,
    user_config: UserConfig,
    prev_manifest: UserManifest,
) -> ConfigPatch:
    # clear launch options we previously set for apps that are no longer configured
    # only if the stored value still matches what we wrote so we don't wipe manual config
    removed_app_ids = set(prev_manifest.launch_options) - set(
        user_config.launch_options
    )
    deletions = [
        Deletion(
            key_path=LOCALCONFIG_APPS_PATH + (str(app_id), "LaunchOptions"),
            expected=prev_manifest.launch_options[app_id],
        )
        for app_id in sorted(removed_app_ids)
    ]

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
        deletions=deletions,
    )


def quote_path(path: str) -> str:
    return f'"{path}"' if path else path


def generate_shortcuts_vdf_patch(
    cfg: PatcherConfig,
    user_id: int,
    user_config: UserConfig,
    prev_manifest: UserManifest,
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

    kv = binary.loads(file_path.read_bytes())

    # hacky way to see which index we should use based on app id and existing shortcuts
    shortcuts = kv.get("shortcuts") or {}
    keys = [int(k) for k in shortcuts.keys()]
    max_index = max(keys) if keys else -1
    index_mapping: dict[int, int] = {}
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

    # remove shortcuts we previously created for non-steam apps that are no longer configured
    # matched by our generated app id, which is unique to us
    removed_app_ids = set(prev_manifest.shortcuts) - set(user_config.non_steam_apps)
    deletions = [
        Deletion(key_path=("shortcuts", str(shortcut_index)))
        for shortcut_index, shortcut in shortcuts.items()
        if shortcut.get("appid") in removed_app_ids
    ]

    return ConfigPatch(
        file_path=file_path,
        file_format="binary-keyvalues",
        data={
            "shortcuts": {
                str(index_mapping[app_id]): {
                    "appid": app_id,
                    "AppName": app.name,
                    "Exe": quote_path(app.target),
                    "StartDir": quote_path(app.start_in),
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
        deletions=deletions,
    )


def apply_patch(config_patch: ConfigPatch) -> bool:
    match config_patch.file_format:
        case "keyvalues":
            return patch_keyvalues(config_patch)
        case "binary-keyvalues":
            return patch_binary_keyvalues(config_patch)
    return True


def desired_manifest(cfg: PatcherConfig, user_config: UserConfig) -> UserManifest:
    return UserManifest(
        compat_tools={
            app_id: compat_tool.name
            for app_id, compat_tool in cfg.compat_tool_mapping.items()
        },
        launch_options=dict(user_config.launch_options),
        shortcuts=list(user_config.non_steam_apps.keys()),
    )


def patch_config_files(cfg: PatcherConfig):
    prev_manifests = {
        user_id: load_manifest(cfg.steam_dir, user_id) for user_id in cfg.users
    }

    # config.vdf is global so cleanup considers compat tools managed for any user
    prev_compat_tools: dict[int, str] = {}
    for manifest in prev_manifests.values():
        prev_compat_tools.update(manifest.compat_tools)

    patch_steps = [
        ("config.vdf", lambda: generate_config_vdf_patch(cfg, prev_compat_tools)),
        *[
            (
                f"localconfig.vdf (user {user_id})",
                lambda user_id=user_id, user=user: generate_localconfig_vdf_patch(
                    cfg, user_id, user, prev_manifests[user_id]
                ),
            )
            for user_id, user in cfg.users.items()
        ],
        *[
            (
                f"shortcuts.vdf (user {user_id})",
                lambda user_id=user_id, user=user: generate_shortcuts_vdf_patch(
                    cfg, user_id, user, prev_manifests[user_id]
                ),
            )
            for user_id, user in cfg.users.items()
        ],
    ]

    failures = 0
    blocked = False
    for description, generate in patch_steps:
        try:
            if not apply_patch(generate()):
                blocked = True
        except Exception:
            failures += 1
            LOG.exception("failed to patch %s", description)

    if failures:
        raise SystemExit(f"{failures} config file(s) failed to patch; see log above")

    if blocked:
        LOG.warning(
            "Steam is running; skipped writes and manifest update. "
            "Close Steam (or enable closeSteam) to apply changes."
        )
        return

    for user_id, user in cfg.users.items():
        try:
            save_manifest(cfg.steam_dir, user_id, desired_manifest(cfg, user))
        except Exception:
            LOG.exception("failed to write manifest for user %s", user_id)
