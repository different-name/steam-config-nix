import logging
import os
from pathlib import Path

from steam_config_patcher.types import GRID_SLOTS, GridArt

LOG = logging.getLogger(__name__)


def desired_grid_files(grid_art: dict[int, GridArt]) -> dict[str, str]:
    files: dict[str, str] = {}
    for app_id, art in grid_art.items():
        for slot, stem_format in GRID_SLOTS:
            source = getattr(art, slot)
            if not source:
                continue
            stem = stem_format.format(app_id=app_id)
            files[f"{stem}{Path(source).suffix}"] = source
    return files


def apply_grid_art(
    steam_dir: Path,
    user_id: int,
    desired: dict[str, str],
    previous: dict[str, str],
) -> dict[str, str]:
    grid_dir = steam_dir.joinpath("userdata", str(user_id), "config", "grid")

    # remove files we previously linked that are no longer wanted,
    # but only while they are still our symlink (never clobber manual art)
    for name, target in previous.items():
        if name in desired:
            continue
        path = grid_dir / name
        if path.is_symlink() and os.readlink(path) == target:
            path.unlink()

    if desired and not grid_dir.is_dir():
        grid_dir.mkdir(parents=True, exist_ok=True)

    written: dict[str, str] = {}
    for name, source in desired.items():
        path = grid_dir / name
        if not (path.is_symlink() and os.readlink(path) == source):
            if path.is_symlink() or path.exists():
                path.unlink()
            path.symlink_to(source)
        written[name] = source

    return written
