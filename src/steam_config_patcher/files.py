import hashlib
import logging
import os
import shutil
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Iterator, Optional

from steam_config_patcher.files_manifest import (
    backup_path,
    load_files_manifest,
    save_files_manifest,
)
from steam_config_patcher.steam import find_app_compat_prefix, find_app_install_dir
from steam_config_patcher.types import (
    FileOp,
    FilesManifest,
    ManagedDir,
    ManagedFile,
    RemoveOp,
)

LOG = logging.getLogger(__name__)

FileKey = tuple[int, str, str]


class FileOpConflict(ValueError):
    pass


@dataclass
class _Placement:
    app_id: int
    location: str
    target: str
    source_file: Path
    overwrite_changes: bool
    executable: Optional[bool]
    specificity: int
    declared: str


def _hash_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _resolve_mode(executable: Optional[bool], source_file: Path) -> int:
    if executable is True:
        return 0o755
    if executable is False:
        return 0o644
    return 0o755 if source_file.stat().st_mode & 0o111 else 0o644


def _specificity(declared_target: str) -> int:
    return len(PurePosixPath(declared_target).parts)


def _is_safe_target(target: str) -> bool:
    path = PurePosixPath(target)
    return bool(target) and not path.is_absolute() and ".." not in path.parts


def _iter_source_files(source: Path) -> Iterator[tuple[str, Path]]:
    if not source.is_dir():
        yield "", source
        return
    for dirpath, dirnames, filenames in os.walk(source):
        dirnames.sort()
        for name in sorted(filenames):
            file_path = Path(dirpath) / name
            yield file_path.relative_to(source).as_posix(), file_path


def _iter_dir_files(base: Path) -> Iterator[Path]:
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames.sort()
        for name in sorted(filenames):
            yield Path(dirpath) / name


def _join_target(declared: str, relpath: str) -> str:
    if not relpath:
        return declared
    return (PurePosixPath(declared) / relpath).as_posix()


def _resolve_placements(file_ops: list[FileOp]) -> dict[FileKey, _Placement]:
    placements: dict[FileKey, _Placement] = {}
    for op in file_ops:
        specificity = _specificity(op.target)
        for relpath, source_file in _iter_source_files(op.source):
            target = _join_target(op.target, relpath)
            if not _is_safe_target(target):
                LOG.warning(
                    "app %d: skipping unsafe %s target %s",
                    op.app_id,
                    op.location,
                    target,
                )
                continue
            key = (op.app_id, op.location, target)
            existing = placements.get(key)
            if existing is None or specificity > existing.specificity:
                placements[key] = _Placement(
                    app_id=op.app_id,
                    location=op.location,
                    target=target,
                    source_file=source_file,
                    overwrite_changes=op.overwrite_changes,
                    executable=op.executable,
                    specificity=specificity,
                    declared=op.target,
                )
            elif specificity == existing.specificity and existing.declared != op.target:
                raise FileOpConflict(
                    f"app {op.app_id}: conflicting file entries for {op.location}/{target}"
                )
    return placements


def _dirs_to_create(root: Path, target: str) -> list[str]:
    created = []
    current = root
    for part in PurePosixPath(target).parts[:-1]:
        current = current / part
        if not current.exists():
            created.append(current.relative_to(root).as_posix())
    return created


def _backup_once(
    steam_dir: Path, app_id: int, location: str, target: str, target_path: Path
) -> None:
    stored = backup_path(steam_dir, app_id, location, target)
    if stored.exists():
        return
    stored.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(target_path, stored, follow_symlinks=False)


def _place_one(
    steam_dir: Path, root: Path, placement: _Placement, prev: Optional[ManagedFile]
) -> Optional[ManagedFile]:
    target_path = root / placement.target
    exists = target_path.exists() or target_path.is_symlink()

    if not placement.overwrite_changes and exists:
        return prev

    source_hash = _hash_file(placement.source_file)
    desired_mode = _resolve_mode(placement.executable, placement.source_file)

    had_backup = prev.had_backup if prev is not None else False
    if exists and prev is None:
        _backup_once(
            steam_dir, placement.app_id, placement.location, placement.target, target_path
        )
        had_backup = True

    entry = ManagedFile(
        app_id=placement.app_id,
        location=placement.location,
        target=placement.target,
        op="place",
        source_hash=source_hash,
        had_backup=had_backup,
    )

    if (
        target_path.is_file()
        and not target_path.is_symlink()
        and _hash_file(target_path) == source_hash
    ):
        if target_path.stat().st_mode & 0o777 != desired_mode:
            target_path.chmod(desired_mode)
        return entry

    target_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(placement.source_file, target_path)
    target_path.chmod(desired_mode)

    return entry


def _remove_targets(
    root: Path, remove_op: RemoveOp, claimed: set[FileKey]
) -> Iterator[str]:
    base = root / remove_op.target
    if base.is_dir() and not base.is_symlink():
        candidates = (p.relative_to(root).as_posix() for p in _iter_dir_files(base))
    elif base.exists() or base.is_symlink():
        candidates = iter([remove_op.target])
    else:
        candidates = iter([])

    for target in candidates:
        if (remove_op.app_id, remove_op.location, target) in claimed:
            continue
        yield target


def _remove_one(
    steam_dir: Path, root: Path, app_id: int, location: str, target: str,
    prev: Optional[ManagedFile],
) -> Optional[ManagedFile]:
    target_path = root / target
    if not (target_path.exists() or target_path.is_symlink()):
        return prev

    had_backup = prev.had_backup if prev is not None else False
    if prev is None:
        _backup_once(steam_dir, app_id, location, target, target_path)
        had_backup = True

    target_path.unlink()

    return ManagedFile(
        app_id=app_id,
        location=location,
        target=target,
        op="remove",
        had_backup=had_backup,
    )


def _cleanup_removed_dir(root: Path, target: str) -> None:
    base = root / target
    if not base.is_dir():
        return
    for dirpath, dirnames, filenames in os.walk(base, topdown=False):
        try:
            Path(dirpath).rmdir()
        except OSError:
            pass


def _cleanup_created_dirs(
    created: set[FileKey], root_for
) -> list[ManagedDir]:
    survivors = []
    for app_id, location, target in sorted(
        created, key=lambda item: len(PurePosixPath(item[2]).parts), reverse=True
    ):
        root = root_for(app_id, location)
        if root is None:
            survivors.append(ManagedDir(app_id, location, target))
            continue
        directory = root / target
        if directory.is_dir():
            try:
                directory.rmdir()
                continue
            except OSError:
                pass
        if directory.exists():
            survivors.append(ManagedDir(app_id, location, target))
    return survivors


def _revert_one(steam_dir: Path, root: Optional[Path], entry: ManagedFile) -> None:
    stored = backup_path(steam_dir, entry.app_id, entry.location, entry.target)

    if root is None:
        if stored.exists():
            stored.unlink()
        return

    target_path = root / entry.target

    if entry.op == "place":
        modified = (
            target_path.is_file()
            and entry.source_hash is not None
            and _hash_file(target_path) != entry.source_hash
        )
        if modified:
            LOG.info("leaving user-modified %s", target_path)
            if stored.exists():
                stored.unlink()
            return
        if target_path.exists() or target_path.is_symlink():
            target_path.unlink()
    else:
        if target_path.exists() or target_path.is_symlink():
            LOG.info("leaving recreated %s", target_path)
            if stored.exists():
                stored.unlink()
            return

    if entry.had_backup and stored.exists():
        target_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(stored), str(target_path))


def apply_file_ops(
    steam_dir: Path, file_ops: list[FileOp], remove_ops: list[RemoveOp]
) -> None:
    prev_manifest = load_files_manifest(steam_dir)
    if (
        not file_ops
        and not remove_ops
        and not prev_manifest.files
        and not prev_manifest.dirs
    ):
        return

    prev = {(e.app_id, e.location, e.target): e for e in prev_manifest.files}

    root_cache: dict[tuple[int, str], Optional[Path]] = {}

    def root_for(app_id: int, location: str) -> Optional[Path]:
        cache_key = (app_id, location)
        if cache_key not in root_cache:
            root_cache[cache_key] = (
                find_app_install_dir(steam_dir, app_id)
                if location == "install"
                else find_app_compat_prefix(steam_dir, app_id)
            )
        return root_cache[cache_key]

    placements = _resolve_placements(file_ops)
    claimed = set(placements.keys())

    new_files: list[ManagedFile] = []
    desired: set[FileKey] = set()
    created_dirs = {(d.app_id, d.location, d.target) for d in prev_manifest.dirs}

    for key, placement in placements.items():
        desired.add(key)
        root = root_for(placement.app_id, placement.location)
        if root is None:
            LOG.warning(
                "app %d: %s root not found, skipping %s",
                placement.app_id,
                placement.location,
                placement.target,
            )
            if key in prev:
                new_files.append(prev[key])
            continue
        for rel in _dirs_to_create(root, placement.target):
            created_dirs.add((placement.app_id, placement.location, rel))
        entry = _place_one(steam_dir, root, placement, prev.get(key))
        if entry is not None:
            new_files.append(entry)

    for remove_op in remove_ops:
        if not _is_safe_target(remove_op.target):
            LOG.warning(
                "app %d: skipping unsafe %s removeFiles path %s",
                remove_op.app_id,
                remove_op.location,
                remove_op.target,
            )
            continue
        root = root_for(remove_op.app_id, remove_op.location)
        if root is None:
            for key, entry in prev.items():
                if (
                    entry.op == "remove"
                    and key[0] == remove_op.app_id
                    and key[1] == remove_op.location
                    and (
                        entry.target == remove_op.target
                        or entry.target.startswith(remove_op.target + "/")
                    )
                ):
                    desired.add(key)
                    new_files.append(entry)
            continue
        base = root / remove_op.target
        base_is_dir = base.is_dir() and not base.is_symlink()
        for target in _remove_targets(root, remove_op, claimed):
            key = (remove_op.app_id, remove_op.location, target)
            desired.add(key)
            entry = _remove_one(
                steam_dir, root, remove_op.app_id, remove_op.location, target,
                prev.get(key),
            )
            if entry is not None:
                new_files.append(entry)
        if base_is_dir:
            _cleanup_removed_dir(root, remove_op.target)

    for key, entry in prev.items():
        if key in desired:
            continue
        _revert_one(steam_dir, root_for(entry.app_id, entry.location), entry)

    survivors = _cleanup_created_dirs(created_dirs, root_for)

    save_files_manifest(steam_dir, FilesManifest(files=new_files, dirs=survivors))
