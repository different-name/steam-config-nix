import json
import logging
from pathlib import Path

from steam_config_patcher.fileio import atomic_write_text
from steam_config_patcher.types import UserManifest

LOG = logging.getLogger(__name__)

MANIFEST_NAME = "steam-config-nix-manifest.json"
MANIFEST_VERSION = 1


def manifest_path(steam_dir: Path, user_id: int) -> Path:
    return steam_dir.joinpath("userdata", str(user_id), "config", MANIFEST_NAME)


def load_manifest(steam_dir: Path, user_id: int) -> UserManifest:
    path = manifest_path(steam_dir, user_id)
    if not path.is_file():
        return UserManifest()

    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        LOG.warning("ignoring unreadable manifest at %s", path, exc_info=True)
        return UserManifest()

    return UserManifest(
        compat_tools={int(k): v for k, v in (raw.get("compat_tools") or {}).items()},
        launch_options={
            int(k): v for k, v in (raw.get("launch_options") or {}).items()
        },
        shortcuts=[int(x) for x in (raw.get("shortcuts") or [])],
    )


def save_manifest(steam_dir: Path, user_id: int, manifest: UserManifest) -> None:
    path = manifest_path(steam_dir, user_id)

    # the user's config dir should already exist (we patch files in it); if it
    # doesn't there's nothing to manage, so skip rather than create stray dirs
    if not path.parent.is_dir():
        return

    data = {
        "version": MANIFEST_VERSION,
        "compat_tools": {str(k): v for k, v in manifest.compat_tools.items()},
        "launch_options": {str(k): v for k, v in manifest.launch_options.items()},
        "shortcuts": manifest.shortcuts,
    }

    atomic_write_text(path, json.dumps(data, indent=2))
