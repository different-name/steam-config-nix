"""Per-app file drops into Steam install dirs and Proton prefixes.

Used for game mods, asset replacements, DLL injections, and first-apply
config templates the game writes back to. Backups of replaced files are
written once next to the target with `.steam-config-nix-backup` suffix on
first apply.
"""

import logging
import shutil
from pathlib import Path
from typing import Optional

from srctools import steam

from steam_config_patcher.types import FileOpConfig, FilesConfig

LOG = logging.getLogger(__name__)
BACKUP_SUFFIX = ".steam-config-nix-backup"


def _find_install_dir(app_id: int) -> Optional[Path]:
    """Resolve `<library>/steamapps/common/<installdir>` for `app_id`.

    Returns `None` when the app is not installed in any registered library.
    """
    try:
        return steam.find_app(app_id).path
    except KeyError:
        return None


def _find_compat_prefix(app_id: int) -> Optional[Path]:
    """Resolve `<library>/steamapps/compatdata/<app_id>/pfx` for `app_id`.

    The compatdata directory lives next to common/ in the same library, so
    we resolve via the install path. Returns `None` if the app or its
    prefix is missing (e.g. the user has never launched the game so Proton
    hasn't created the prefix yet).
    """
    install = _find_install_dir(app_id)
    if install is None:
        return None
    # …/<library>/steamapps/common/<installdir>
    #   .parents[0] = …/<library>/steamapps/common
    #   .parents[1] = …/<library>/steamapps
    pfx = install.parents[1] / "compatdata" / str(app_id) / "pfx"
    return pfx if pfx.is_dir() else None


def _resolve_root(app_id: int, location: str) -> Optional[Path]:
    if location == "install":
        return _find_install_dir(app_id)
    if location == "prefix":
        return _find_compat_prefix(app_id)
    raise ValueError(f"unknown location {location!r}")


def _apply_file_op(app_id: int, op: FileOpConfig) -> None:
    root = _resolve_root(app_id, op.location)
    if root is None:
        LOG.warning(
            "app %d: %s root not found, skipping %s",
            app_id,
            op.location,
            op.target,
        )
        return

    target = root / op.target
    source = Path(op.source)
    target_existed = target.exists()

    # `replace` is a no-op when the target doesn't exist; the operator opted
    # into "only act when the file is already there".
    if not target_existed and op.mode == "replace":
        LOG.warning(
            "app %d: target %s does not exist (mode=replace), skipping",
            app_id,
            target,
        )
        return

    # `init` writes only on first apply, then it's user-owned. Even if the
    # source content drifted (e.g. a new tuning landed in the host config),
    # leave the on-disk file alone so in-game overlay edits and other user
    # changes are preserved across re-applies. Push a new template by
    # deleting the target and re-running.
    if target_existed and op.mode == "init":
        return

    # Already applied — bytes match. Skip the rewrite + chmod churn.
    if target_existed and target.is_file() and source.is_file():
        if target.read_bytes() == source.read_bytes():
            return

    # Back up the original (once), if it existed. We never overwrite an
    # existing backup, so the very first state we saw is what gets preserved.
    backup = target.with_name(target.name + BACKUP_SUFFIX)
    if target_existed and not backup.exists():
        shutil.copy2(target, backup)
        LOG.info("backed up %s -> %s", target, backup)

    if not target_existed:
        target.parent.mkdir(parents=True, exist_ok=True)

    shutil.copy2(source, target)
    # /nix/store sources are 0o444; copy2 carries those bits across, leaving
    # the dropped file read-only. Any app that writes back to a dropped
    # config file (in-game overlays, save files, settings panels) would then
    # fail with EACCES. Force a writable mode so user/in-app edits can
    # persist; `init` mode then keeps them across re-applies.
    target.chmod(0o644)

    if op.mode == "init":
        verb = "initialized"
    elif target_existed:
        verb = "replaced"
    else:
        verb = "created"
    LOG.info("%s %s", verb, target)


def apply_file_drops(file_drops: list[FilesConfig]) -> None:
    for entry in file_drops:
        for op in entry.files:
            _apply_file_op(entry.app_id, op)
