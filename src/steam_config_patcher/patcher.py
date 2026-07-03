import logging
from typing import Iterable, Optional

from steam_config_patcher.fileio import atomic_write_bytes
from steam_config_patcher.formats.binary_keyvalues import prepare_binary_keyvalues
from steam_config_patcher.formats.keyvalues import prepare_keyvalues
from steam_config_patcher.manifest import load_manifest, save_manifest
from steam_config_patcher.steam import (
    close_steam,
    find_app_manifest,
    game_is_running,
    steam_is_running,
    wait_for_game_exit,
    wait_for_steam_exit,
)
from steam_config_patcher.types import (
    APPMANIFEST_BETA_KEY,
    APPMANIFEST_FILE_PREFIX,
    APPMANIFEST_LANGUAGE_KEY,
    APPMANIFEST_USER_CONFIG_PATH,
    COMPAT_TOOL_MAPPING_PATH,
    CONFIG_FILE,
    LOCALCONFIG_APPS_PATH,
    LOCALCONFIG_FILE,
    ConfigPatch,
    Deletion,
    KeyValuesType,
    ManagedKey,
    PatcherConfig,
    UserConfig,
    UserManifest,
)
from steam_config_patcher.vdf import binary

LOG = logging.getLogger(__name__)

KeyValuesLeaves = dict[tuple[str, ...], str]


def nest_leaves(leaves: KeyValuesLeaves) -> KeyValuesType:
    tree: KeyValuesType = {}
    for key_path, value in leaves.items():
        node = tree
        for key in key_path[:-1]:
            node = node.setdefault(key, {})
        node[key_path[-1]] = value
    return tree


def config_vdf_state(cfg: PatcherConfig) -> tuple[KeyValuesLeaves, list[ManagedKey]]:
    leaves: KeyValuesLeaves = {}
    managed_keys = []

    for app_id, compat_tool in cfg.compat_tool_mapping.items():
        block_path = COMPAT_TOOL_MAPPING_PATH + (str(app_id),)
        leaves[block_path + ("config",)] = ""
        leaves[block_path + ("name",)] = compat_tool.name
        leaves[block_path + ("priority",)] = str(compat_tool.priority)
        managed_keys.append(
            ManagedKey(
                file=CONFIG_FILE,
                key_path=block_path,
                guard_path=("name",),
                expected=compat_tool.name,
            )
        )

    return leaves, managed_keys


def appmanifest_file_id(app_id: int) -> str:
    return f"{APPMANIFEST_FILE_PREFIX}{app_id}"


def appmanifest_app_id(file_id: str) -> Optional[int]:
    if not file_id.startswith(APPMANIFEST_FILE_PREFIX):
        return None
    suffix = file_id.removeprefix(APPMANIFEST_FILE_PREFIX)
    return int(suffix) if suffix.isdigit() else None


def appmanifest_user_config(cfg: PatcherConfig, app_id: int) -> dict[str, str]:
    entries = {}
    beta_branch = cfg.game_betas.get(app_id)
    if beta_branch is not None:
        entries[APPMANIFEST_BETA_KEY] = beta_branch
    language = cfg.game_languages.get(app_id)
    if language is not None:
        entries[APPMANIFEST_LANGUAGE_KEY] = language
    return entries


def game_appmanifest_keys(cfg: PatcherConfig) -> list[ManagedKey]:
    return [
        ManagedKey(
            file=appmanifest_file_id(app_id),
            key_path=APPMANIFEST_USER_CONFIG_PATH + (sub_key,),
            expected=value,
        )
        for app_id in configured_appmanifest_ids(cfg)
        for sub_key, value in appmanifest_user_config(cfg, app_id).items()
    ]


def configured_appmanifest_ids(cfg: PatcherConfig) -> set[int]:
    return set(cfg.game_betas) | set(cfg.game_languages)


def generate_appmanifest_patch(
    cfg: PatcherConfig, app_id: int, prev_keys: Iterable[ManagedKey]
) -> Optional[ConfigPatch]:
    file_id = appmanifest_file_id(app_id)
    entries = appmanifest_user_config(cfg, app_id)

    file_path = find_app_manifest(cfg.steam_dir, app_id)
    if file_path is None:
        if entries:
            LOG.warning(
                "app %s is not installed, cannot apply %s",
                app_id,
                ", ".join(sorted(entries)),
            )
        return None

    data: KeyValuesType = {}
    if entries:
        data = {"AppState": {"UserConfig": dict(entries)}}

    desired_keys = [
        ManagedKey(
            file=file_id,
            key_path=APPMANIFEST_USER_CONFIG_PATH + (sub_key,),
            expected=value,
        )
        for sub_key, value in entries.items()
    ]

    return ConfigPatch(
        file_path=file_path,
        file_format="keyvalues",
        data=data,
        deletions=cleanup_deletions(prev_keys, desired_keys, file_id),
    )


def localconfig_vdf_state(
    user_config: UserConfig,
) -> tuple[KeyValuesLeaves, list[ManagedKey]]:
    leaves: KeyValuesLeaves = {}
    managed_keys = []

    for app_id, launch_options in user_config.launch_options.items():
        key_path = LOCALCONFIG_APPS_PATH + (str(app_id), "LaunchOptions")
        leaves[key_path] = launch_options
        managed_keys.append(
            ManagedKey(
                file=LOCALCONFIG_FILE,
                key_path=key_path,
                expected=launch_options,
            )
        )

    return leaves, managed_keys


def cleanup_deletions(
    prev_keys: Iterable[ManagedKey],
    desired_keys: Iterable[ManagedKey],
    file_id: str,
) -> list[Deletion]:
    desired_paths = {key.key_path for key in desired_keys if key.file == file_id}

    removed: dict[tuple[str, ...], ManagedKey] = {}
    for key in prev_keys:
        if key.file == file_id and key.key_path not in desired_paths:
            removed.setdefault(key.key_path, key)

    return [removed[key_path].to_deletion() for key_path in sorted(removed)]


def generate_config_vdf_patch(
    cfg: PatcherConfig, prev_keys: Iterable[ManagedKey]
) -> ConfigPatch:
    leaves, desired_keys = config_vdf_state(cfg)

    return ConfigPatch(
        file_path=cfg.steam_dir.joinpath("config", "config.vdf"),
        file_format="keyvalues",
        data=nest_leaves(leaves),
        deletions=cleanup_deletions(prev_keys, desired_keys, CONFIG_FILE),
    )


def generate_localconfig_vdf_patch(
    cfg: PatcherConfig,
    user_id: int,
    user_config: UserConfig,
    prev_manifest: UserManifest,
) -> ConfigPatch:
    leaves, desired_keys = localconfig_vdf_state(user_config)

    return ConfigPatch(
        file_path=cfg.steam_dir.joinpath(
            "userdata", str(user_id), "config", "localconfig.vdf"
        ),
        file_format="keyvalues",
        data=nest_leaves(leaves),
        deletions=cleanup_deletions(
            prev_manifest.managed_keys, desired_keys, LOCALCONFIG_FILE
        ),
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
        deletions=deletions,
    )


def prepare_patch(config_patch: ConfigPatch) -> Optional[bytes]:
    match config_patch.file_format:
        case "keyvalues":
            return prepare_keyvalues(config_patch)
        case "binary-keyvalues":
            return prepare_binary_keyvalues(config_patch)
    return None


def desired_manifest(cfg: PatcherConfig, user_config: UserConfig) -> UserManifest:
    _, config_keys = config_vdf_state(cfg)
    _, localconfig_keys = localconfig_vdf_state(user_config)

    return UserManifest(
        managed_keys=config_keys + game_appmanifest_keys(cfg) + localconfig_keys,
        shortcuts=list(user_config.non_steam_apps.keys()),
    )


def patch_config_files(cfg: PatcherConfig):
    prev_manifests = {
        user_id: load_manifest(cfg.steam_dir, user_id) for user_id in cfg.users
    }

    # config.vdf is global so cleanup considers keys managed for any user
    all_prev_keys = [
        key for manifest in prev_manifests.values() for key in manifest.managed_keys
    ]

    appmanifest_app_ids = sorted(
        configured_appmanifest_ids(cfg)
        | {
            app_id
            for key in all_prev_keys
            if (app_id := appmanifest_app_id(key.file)) is not None
        }
    )

    patch_steps = [
        ("config.vdf", lambda: generate_config_vdf_patch(cfg, all_prev_keys)),
        *[
            (
                f"appmanifest_{app_id}.acf",
                lambda app_id=app_id: generate_appmanifest_patch(
                    cfg, app_id, all_prev_keys
                ),
            )
            for app_id in appmanifest_app_ids
        ],
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

    failed: set[str] = set()

    def prepare_all():
        prepared = []
        for description, generate in patch_steps:
            try:
                config_patch = generate()
                data = None if config_patch is None else prepare_patch(config_patch)
            except Exception:
                failed.add(description)
                LOG.exception("failed to prepare %s", description)
                continue
            if data is not None:
                prepared.append((description, config_patch.file_path, data))
        return prepared

    prepared = prepare_all()

    blocked = False
    if prepared and steam_is_running():
        if cfg.on_steam_running == "skip":
            blocked = True
        else:
            if cfg.on_steam_running == "wait":
                LOG.info("steam is running, waiting for it to exit")
                wait_for_steam_exit()
            else:
                if cfg.on_steam_running == "close" and game_is_running():
                    LOG.info(
                        "a game is running, waiting for it to exit before closing steam"
                    )
                    wait_for_game_exit()
                close_steam()
            prepared = prepare_all()

    if not blocked:
        for description, file_path, data in prepared:
            try:
                atomic_write_bytes(file_path, data)
            except Exception:
                failed.add(description)
                LOG.exception("failed to write %s", description)

    if failed:
        raise SystemExit(f"{len(failed)} config file(s) failed to patch; see log above")

    if blocked:
        LOG.warning(
            "Steam is running; skipped writes and manifest update. "
            'Close Steam, or set onSteamRunning to "wait" or "close" to apply automatically.'
        )
        return

    for user_id, user in cfg.users.items():
        try:
            save_manifest(cfg.steam_dir, user_id, desired_manifest(cfg, user))
        except Exception:
            LOG.exception("failed to write manifest for user %s", user_id)
