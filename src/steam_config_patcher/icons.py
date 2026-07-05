import io
import logging
import os
from pathlib import Path
from typing import Optional

from PIL import Image

from steam_config_patcher.fileio import atomic_write_bytes
from steam_config_patcher.vdf import appinfo

LOG = logging.getLogger(__name__)

ICON_PREFIX = "steam-config-nix-"


def _hicolor_dir() -> Path:
    return Path.home().joinpath(".local", "share", "icons", "hicolor")


def _icon_search_bases() -> list[Path]:
    bases = [Path.home() / ".local" / "share" / "icons"]
    data_dirs = os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"
    for entry in data_dirs.split(":"):
        if entry:
            bases.append(Path(entry) / "icons")
    return bases


def _remove_managed_icons(hicolor: Path) -> None:
    if not hicolor.is_dir():
        return
    for path in hicolor.glob(f"*/apps/{ICON_PREFIX}*"):
        try:
            path.unlink()
        except OSError:
            LOG.warning("could not remove %s", path, exc_info=True)


def _librarycache_icon(steam_dir: Path, app_id: int, hash_: str) -> Optional[Path]:
    directory = steam_dir.joinpath("appcache", "librarycache", str(app_id))
    for ext in (".jpg", ".png", ".ico"):
        candidate = directory / f"{hash_}{ext}"
        if candidate.is_file():
            return candidate
    return None


def _render_png(source: Path) -> tuple[bytes, tuple[int, int]]:
    with Image.open(source) as image:
        rgba = image.convert("RGBA")
        buffer = io.BytesIO()
        rgba.save(buffer, format="PNG")
        return buffer.getvalue(), rgba.size


def _fallback_icon() -> Optional[Path]:
    best: Optional[Path] = None
    best_size = -1
    for base in _icon_search_bases():
        hicolor = base / "hicolor"
        if not hicolor.is_dir():
            continue
        for size_dir in hicolor.iterdir():
            candidate = size_dir / "apps" / "steam.png"
            if not candidate.is_file():
                continue
            try:
                size = int(size_dir.name.split("x")[0])
            except ValueError:
                size = 0
            if size > best_size:
                best_size = size
                best = candidate
    return best


def _write_icon(hicolor: Path, app_id: int, data: bytes, size: tuple[int, int]) -> None:
    width, height = size
    directory = hicolor / f"{width}x{height}" / "apps"
    directory.mkdir(parents=True, exist_ok=True)
    atomic_write_bytes(directory / f"{ICON_PREFIX}{app_id}.png", data)


def _resolve_source(
    steam_dir: Path, app_id: int, common: dict[int, dict]
) -> Optional[Path]:
    entry = common.get(app_id)
    if entry is None:
        return None
    hash_ = appinfo.icon_hash(entry)
    if hash_ is None:
        return None
    return _librarycache_icon(steam_dir, app_id, hash_)


def apply_library_icons(steam_dir: Path, app_ids: set[int]) -> None:
    hicolor = _hicolor_dir()
    _remove_managed_icons(hicolor)
    if not app_ids:
        return

    common: dict[int, dict] = {}
    appinfo_path = steam_dir.joinpath("appcache", "appinfo.vdf")
    try:
        common = appinfo.load_common(appinfo_path.read_bytes(), app_ids=app_ids)
    except FileNotFoundError:
        LOG.warning("appinfo.vdf not found, using fallback icons")
    except appinfo.AppInfoError as error:
        LOG.warning("could not parse appinfo.vdf (%s), using fallback icons", error)

    fallback = _fallback_icon()

    for app_id in sorted(app_ids):
        source = _resolve_source(steam_dir, app_id, common)
        if source is None and fallback is not None:
            source = fallback
        if source is None:
            LOG.warning("no icon available for app %s", app_id)
            continue
        try:
            data, size = _render_png(source)
        except Exception:
            LOG.warning("could not read icon for app %s", app_id, exc_info=True)
            continue
        _write_icon(hicolor, app_id, data, size)
