import logging
import os
import shutil
from pathlib import Path

LOG = logging.getLogger(__name__)

LEGACY_MANIFEST_NAME = "steam-config-nix-manifest.json"
LEGACY_FILES_MANIFEST_NAME = "steam-config-nix-files.json"
LEGACY_BACKUP_DIR_NAME = "steam-config-nix-backups"


def state_base() -> Path:
    data_home = os.environ.get("XDG_DATA_HOME")
    base = Path(data_home) if data_home else Path.home() / ".local" / "share"
    return base / "steam-config-nix"


def user_manifest_path(user_id: int) -> Path:
    return state_base() / "users" / str(user_id) / "manifest.json"


def files_manifest_path() -> Path:
    return state_base() / "files.json"


def backup_root() -> Path:
    return state_base() / "backups"


def legacy_manifest_path(steam_dir: Path, user_id: int) -> Path:
    return steam_dir.joinpath("userdata", str(user_id), "config", LEGACY_MANIFEST_NAME)


def legacy_files_manifest_path(steam_dir: Path) -> Path:
    return steam_dir.joinpath("config", LEGACY_FILES_MANIFEST_NAME)


def legacy_backup_root(steam_dir: Path) -> Path:
    return steam_dir.joinpath("config", LEGACY_BACKUP_DIR_NAME)


def _merge_dir(source: Path, destination: Path) -> None:
    for path in sorted(source.rglob("*")):
        if path.is_dir() and not path.is_symlink():
            continue
        moved = destination / path.relative_to(source)
        if moved.exists() or moved.is_symlink():
            continue
        moved.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(path), str(moved))
    for path in sorted(source.rglob("*"), reverse=True) + [source]:
        if path.is_dir() and not path.is_symlink() and not any(path.iterdir()):
            path.rmdir()


def _move(source: Path, destination: Path) -> None:
    if not source.exists():
        return
    if destination.exists():
        # rolling a generation back writes the legacy path again, and leaving it there strands the records in it
        if source.is_dir() and destination.is_dir():
            _merge_dir(source, destination)
        if source.exists():
            LOG.warning(
                "%s is left behind because %s already holds records", source, destination
            )
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(source), str(destination))
    LOG.info("moved %s out of steam's directory to %s", source.name, destination)


# steam rewrites its own directories, so our records cannot live inside them
def relocate_state(steam_dir: Path, user_ids: list[int]) -> None:
    for user_id in user_ids:
        _move(legacy_manifest_path(steam_dir, user_id), user_manifest_path(user_id))
    _move(legacy_files_manifest_path(steam_dir), files_manifest_path())
    _move(legacy_backup_root(steam_dir), backup_root())
