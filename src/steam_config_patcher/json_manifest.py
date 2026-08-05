import json
import logging
from collections.abc import Callable
from pathlib import Path

from steam_config_patcher.fileio import atomic_write_text

LOG = logging.getLogger(__name__)


def load_json_manifest[T](
    path: Path, parse: Callable[[dict], T | None], default: T
) -> T:
    if not path.is_file():
        return default
    try:
        result = parse(json.loads(path.read_text(encoding="utf-8")))
    except Exception:
        LOG.warning("ignoring unreadable manifest at %s", path, exc_info=True)
        return default
    return default if result is None else result


def save_json_manifest(path: Path, data: dict) -> None:
    if not path.parent.is_dir():
        return
    atomic_write_text(path, json.dumps(data, indent=2))
