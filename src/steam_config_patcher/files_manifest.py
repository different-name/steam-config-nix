import logging
from pathlib import Path
from typing import Optional

from steam_config_patcher.json_manifest import load_json_manifest, save_json_manifest
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


def _parse(raw: dict) -> Optional[FilesManifest]:
    version = raw.get("version")
    if version != FILES_MANIFEST_VERSION:
        LOG.warning("ignoring files manifest with unknown version %s", version)
        return None
    return FilesManifest(
        files=[
            ManagedFile(
                app_id=int(entry["app_id"]),
                location=entry["location"],
                target=entry["target"],
                op=entry["op"],
                source_hash=entry.get("source_hash"),
                had_backup=bool(entry.get("had_backup", False)),
                source_path=entry.get("source_path"),
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


def load_files_manifest(steam_dir: Path) -> FilesManifest:
    return load_json_manifest(files_manifest_path(steam_dir), _parse, FilesManifest())


def save_files_manifest(steam_dir: Path, manifest: FilesManifest) -> None:
    save_json_manifest(
        files_manifest_path(steam_dir),
        {
            "version": FILES_MANIFEST_VERSION,
            "files": [
                {
                    "app_id": entry.app_id,
                    "location": entry.location,
                    "target": entry.target,
                    "op": entry.op,
                    "source_hash": entry.source_hash,
                    "had_backup": entry.had_backup,
                    "source_path": entry.source_path,
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
        },
    )
