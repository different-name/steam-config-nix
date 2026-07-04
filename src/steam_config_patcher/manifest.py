import json
import logging
from pathlib import Path

from steam_config_patcher.fileio import atomic_write_text
from steam_config_patcher.types import (
    COMPAT_TOOL_MAPPING_PATH,
    CONFIG_FILE,
    LOCALCONFIG_APPS_PATH,
    LOCALCONFIG_FILE,
    ManagedKey,
    UserManifest,
)

LOG = logging.getLogger(__name__)

MANIFEST_NAME = "steam-config-nix-manifest.json"
MANIFEST_VERSION = 2


def manifest_path(steam_dir: Path, user_id: int) -> Path:
    return steam_dir.joinpath("userdata", str(user_id), "config", MANIFEST_NAME)


def _parse_v1(raw: dict) -> UserManifest:
    managed_keys = [
        ManagedKey(
            file=CONFIG_FILE,
            key_path=COMPAT_TOOL_MAPPING_PATH + (str(app_id),),
            guard_path=("name",),
            expected=name,
        )
        for app_id, name in (raw.get("compat_tools") or {}).items()
    ] + [
        ManagedKey(
            file=LOCALCONFIG_FILE,
            key_path=LOCALCONFIG_APPS_PATH + (str(app_id), "LaunchOptions"),
            expected=launch_options,
        )
        for app_id, launch_options in (raw.get("launch_options") or {}).items()
    ]

    return UserManifest(
        managed_keys=managed_keys,
        shortcuts=[int(x) for x in (raw.get("shortcuts") or [])],
    )


def _parse_v2(raw: dict) -> UserManifest:
    return UserManifest(
        managed_keys=[
            ManagedKey(
                file=entry["file"],
                key_path=tuple(entry["path"]),
                guard_path=tuple(entry.get("guard") or ()),
                expected=entry.get("value"),
            )
            for entry in (raw.get("managed_keys") or [])
        ],
        shortcuts=[int(x) for x in (raw.get("shortcuts") or [])],
        grid_art={str(k): str(v) for k, v in (raw.get("grid_art") or {}).items()},
    )


def load_manifest(steam_dir: Path, user_id: int) -> UserManifest:
    path = manifest_path(steam_dir, user_id)
    if not path.is_file():
        return UserManifest()

    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
        version = raw.get("version")
        if version == 1:
            return _parse_v1(raw)
        if version == MANIFEST_VERSION:
            return _parse_v2(raw)
        LOG.warning("ignoring manifest with unknown version %s at %s", version, path)
    except Exception:
        LOG.warning("ignoring unreadable manifest at %s", path, exc_info=True)

    return UserManifest()


def save_manifest(steam_dir: Path, user_id: int, manifest: UserManifest) -> None:
    path = manifest_path(steam_dir, user_id)

    # the user's config dir should already exist (we patch files in it); if it
    # doesn't there's nothing to manage, so skip rather than create stray dirs
    if not path.parent.is_dir():
        return

    data = {
        "version": MANIFEST_VERSION,
        "managed_keys": [
            {
                "file": key.file,
                "path": list(key.key_path),
                "guard": list(key.guard_path),
                "value": key.expected,
            }
            for key in manifest.managed_keys
        ],
        "shortcuts": manifest.shortcuts,
        "grid_art": manifest.grid_art,
    }

    atomic_write_text(path, json.dumps(data, indent=2))
