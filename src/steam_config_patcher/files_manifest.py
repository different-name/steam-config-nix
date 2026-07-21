import json
import logging
from pathlib import Path

from steam_config_patcher.fileio import atomic_write_text
from steam_config_patcher.types import FilesManifest, ManagedDir, ManagedFile

LOG = logging.getLogger(__name__)

FILES_MANIFEST_NAME = "steam-config-nix-files.json"
FILES_MANIFEST_VERSION = 1
BACKUP_DIR_NAME = "steam-config-nix-backups"


def files_manifest_path(steam_dir: Path) -> Path:
    return steam_dir.joinpath("config", FILES_MANIFEST_NAME)


def backup_path(steam_dir: Path, app_id: int, location: str, target: str) -> Path:
    return steam_dir.joinpath(
        "config", BACKUP_DIR_NAME, str(app_id), location, target
    )


def load_files_manifest(steam_dir: Path) -> FilesManifest:
    path = files_manifest_path(steam_dir)
    if not path.is_file():
        return FilesManifest()

    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
        version = raw.get("version")
        if version != FILES_MANIFEST_VERSION:
            LOG.warning(
                "ignoring files manifest with unknown version %s at %s", version, path
            )
            return FilesManifest()
        return FilesManifest(
            files=[
                ManagedFile(
                    app_id=int(entry["app_id"]),
                    location=entry["location"],
                    target=entry["target"],
                    op=entry["op"],
                    source_hash=entry.get("source_hash"),
                    had_backup=bool(entry.get("had_backup", False)),
                )
                for entry in (raw.get("files") or [])
            ],
            dirs=[
                ManagedDir(
                    app_id=int(entry["app_id"]),
                    location=entry["location"],
                    target=entry["target"],
                )
                for entry in (raw.get("dirs") or [])
            ],
        )
    except Exception:
        LOG.warning("ignoring unreadable files manifest at %s", path, exc_info=True)
        return FilesManifest()


def save_files_manifest(steam_dir: Path, manifest: FilesManifest) -> None:
    path = files_manifest_path(steam_dir)

    if not path.parent.is_dir():
        return

    data = {
        "version": FILES_MANIFEST_VERSION,
        "files": [
            {
                "app_id": entry.app_id,
                "location": entry.location,
                "target": entry.target,
                "op": entry.op,
                "source_hash": entry.source_hash,
                "had_backup": entry.had_backup,
            }
            for entry in manifest.files
        ],
        "dirs": [
            {
                "app_id": entry.app_id,
                "location": entry.location,
                "target": entry.target,
            }
            for entry in manifest.dirs
        ],
    }

    atomic_write_text(path, json.dumps(data, indent=2))
