import configparser
import hashlib
import io
import json
import logging
import os
import shutil
from collections.abc import Callable, Iterator
from dataclasses import dataclass
from pathlib import Path, PurePosixPath

from steam_config_patcher.fileio import atomic_write_bytes
from steam_config_patcher.files_manifest import (
    backup_path,
    load_files_manifest,
    save_files_manifest,
)
from steam_config_patcher.steam import find_app_compat_prefix, find_app_install_dir
from steam_config_patcher.types import (
    FileLocation,
    FileOp,
    FilesManifest,
    ManagedDir,
    ManagedFile,
    PatchOp,
    RemoveOp,
)

LOG = logging.getLogger(__name__)

type FileKey = tuple[int, FileLocation, str]


class FileOpConflict(ValueError):
    pass


@dataclass
class _Placement:
    app_id: int
    location: FileLocation
    target: str
    source_file: Path
    mode: str
    executable: bool | None
    specificity: int
    declared: str


def _hash_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _resolve_mode(executable: bool | None, source_file: Path, mode: str) -> int:
    if executable is True:
        perm = 0o755
    elif executable is False:
        perm = 0o644
    else:
        perm = 0o755 if source_file.stat().st_mode & 0o111 else 0o644
    if mode == "lock":
        perm &= ~0o222
    return perm


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
                    mode=op.mode,
                    executable=op.executable,
                    specificity=specificity,
                    declared=op.target,
                )
            elif specificity == existing.specificity:
                raise FileOpConflict(
                    f"app {op.app_id}: conflicting file entries for {op.location}/{target}"
                )
    return placements


def _dirs_to_create(root: Path, target: str) -> list[str]:
    created: list[str] = []
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


def _atomic_place(source_file: Path, target_path: Path, mode: int) -> None:
    tmp = target_path.with_name(target_path.name + ".steam-config-nix-tmp")
    shutil.copy2(source_file, tmp)
    tmp.chmod(mode)
    os.replace(tmp, target_path)


def _place_one(
    steam_dir: Path, root: Path, placement: _Placement, prev: ManagedFile | None
) -> ManagedFile | None:
    target_path = root / placement.target
    is_symlink = target_path.is_symlink()
    exists = target_path.exists() or is_symlink

    if exists and not is_symlink and target_path.is_dir():
        LOG.warning(
            "app %d: %s target %s is a directory, skipping",
            placement.app_id,
            placement.location,
            placement.target,
        )
        return prev

    if placement.mode == "seed" and exists:
        return prev

    source_path = str(placement.source_file)
    if prev is not None and prev.source_path == source_path and prev.source_hash is not None:
        source_hash = prev.source_hash
    else:
        source_hash = _hash_file(placement.source_file)
    desired_mode = _resolve_mode(
        placement.executable, placement.source_file, placement.mode
    )

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
        source_path=source_path,
    )

    if (
        not is_symlink
        and target_path.is_file()
        and target_path.stat().st_size == placement.source_file.stat().st_size
        and _hash_file(target_path) == source_hash
    ):
        if target_path.stat().st_mode & 0o777 != desired_mode:
            target_path.chmod(desired_mode)
        return entry

    target_path.parent.mkdir(parents=True, exist_ok=True)
    _atomic_place(placement.source_file, target_path, desired_mode)

    return entry


def _deep_merge(base: dict, overlay: dict) -> dict:
    result = dict(base)
    for key, value in overlay.items():
        existing = result.get(key)
        if isinstance(existing, dict) and isinstance(value, dict):
            result[key] = _deep_merge(existing, value)
        else:
            result[key] = value
    return result


def _render_json_patch(content: dict, existing: bytes) -> bytes:
    base = json.loads(existing) if existing.strip() else {}
    if not isinstance(base, dict):
        base = {}
    merged = _deep_merge(base, content)
    return (json.dumps(merged, indent=2) + "\n").encode("utf-8")


class _CaseSensitiveConfigParser(configparser.ConfigParser):
    def optionxform(self, optionstr: str) -> str:
        return optionstr


def _render_ini_patch(content: dict, existing: bytes) -> bytes:
    parser = _CaseSensitiveConfigParser(interpolation=None)
    if existing.strip():
        parser.read_string(existing.decode("utf-8"))
    for section, values in content.items():
        if not parser.has_section(section):
            parser.add_section(section)
        for key, value in values.items():
            parser.set(section, key, str(value))
    out = io.StringIO()
    parser.write(out)
    return out.getvalue().encode("utf-8")


def _render_patch(patch_op: PatchOp, existing: bytes) -> bytes:
    if patch_op.format == "json":
        return _render_json_patch(patch_op.content, existing)
    return _render_ini_patch(patch_op.content, existing)


def _patch_one(
    steam_dir: Path, root: Path, patch_op: PatchOp, prev: ManagedFile | None
) -> ManagedFile | None:
    target_path = root / patch_op.target
    is_symlink = target_path.is_symlink()
    exists = target_path.exists() or is_symlink

    if exists and not is_symlink and target_path.is_dir():
        LOG.warning(
            "app %d: %s patch target %s is a directory, skipping",
            patch_op.app_id,
            patch_op.location,
            patch_op.target,
        )
        return prev

    if not exists:
        if patch_op.when_missing == "skip":
            print(
                f"steam-config-nix: waiting for {patch_op.target} "
                "to be created by the game"
            )
            return prev
        existing = b""
        had_backup = False
    else:
        existing = target_path.read_bytes()
        had_backup = prev.had_backup if prev is not None else False
        if prev is None:
            _backup_once(
                steam_dir,
                patch_op.app_id,
                patch_op.location,
                patch_op.target,
                target_path,
            )
            had_backup = True

    merged = _render_patch(patch_op, existing)
    source_hash = hashlib.sha256(merged).hexdigest()

    entry = ManagedFile(
        app_id=patch_op.app_id,
        location=patch_op.location,
        target=patch_op.target,
        op="patch",
        source_hash=source_hash,
        had_backup=had_backup,
    )

    already_current = (
        exists and not is_symlink and target_path.is_file() and existing == merged
    )
    if not already_current:
        target_path.parent.mkdir(parents=True, exist_ok=True)
        atomic_write_bytes(target_path, merged)

    return entry


def _remove_targets(
    root: Path, remove_op: RemoveOp, claimed: set[FileKey]
) -> Iterator[str]:
    base = root / remove_op.target
    if base.is_dir() and not base.is_symlink():
        candidates: Iterator[str] = (
            p.relative_to(root).as_posix() for p in _iter_dir_files(base)
        )
    elif base.exists() or base.is_symlink():
        candidates = iter([remove_op.target])
    else:
        candidates = iter([])

    for target in candidates:
        if (remove_op.app_id, remove_op.location, target) in claimed:
            continue
        yield target


def _remove_one(
    steam_dir: Path, root: Path, app_id: int, location: FileLocation, target: str,
    prev: ManagedFile | None,
) -> ManagedFile | None:
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
    created: set[FileKey], root_for: Callable[[int, str], Path | None]
) -> list[ManagedDir]:
    survivors: list[ManagedDir] = []
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


def _revert_one(steam_dir: Path, root: Path | None, entry: ManagedFile) -> None:
    stored = backup_path(steam_dir, entry.app_id, entry.location, entry.target)

    if root is None:
        if stored.exists():
            stored.unlink()
        return

    target_path = root / entry.target

    if entry.op in ("place", "patch"):
        if target_path.is_dir() and not target_path.is_symlink():
            LOG.info("leaving directory at former file target %s", target_path)
            if stored.exists():
                stored.unlink()
            return
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
    steam_dir: Path,
    file_ops: list[FileOp],
    remove_ops: list[RemoveOp],
    patch_ops: list[PatchOp] | None = None,
) -> None:
    patch_ops = patch_ops or []
    prev_manifest = load_files_manifest(steam_dir)
    if (
        not file_ops
        and not remove_ops
        and not patch_ops
        and not prev_manifest.files
        and not prev_manifest.dirs
    ):
        return

    prev: dict[FileKey, ManagedFile] = {
        (e.app_id, e.location, e.target): e for e in prev_manifest.files
    }

    root_cache: dict[tuple[int, str], Path | None] = {}

    def root_for(app_id: int, location: str) -> Path | None:
        cache_key = (app_id, location)
        if cache_key not in root_cache:
            root_cache[cache_key] = (
                find_app_install_dir(steam_dir, app_id)
                if location == "game"
                else find_app_compat_prefix(steam_dir, app_id)
            )
        return root_cache[cache_key]

    placements = _resolve_placements(file_ops)
    claimed = set(placements.keys())

    new_files: list[ManagedFile] = []
    desired: set[FileKey] = set()
    created_dirs: set[FileKey] = {
        (d.app_id, d.location, d.target) for d in prev_manifest.dirs
    }

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

    for patch_op in patch_ops:
        if not _is_safe_target(patch_op.target):
            LOG.warning(
                "app %d: skipping unsafe %s patch target %s",
                patch_op.app_id,
                patch_op.location,
                patch_op.target,
            )
            continue
        key = (patch_op.app_id, patch_op.location, patch_op.target)
        claimed.add(key)
        desired.add(key)
        root = root_for(patch_op.app_id, patch_op.location)
        if root is None:
            LOG.warning(
                "app %d: %s root not found, skipping patch %s",
                patch_op.app_id,
                patch_op.location,
                patch_op.target,
            )
            if key in prev:
                new_files.append(prev[key])
            continue
        target_path = root / patch_op.target
        will_create = (
            not (target_path.exists() or target_path.is_symlink())
            and patch_op.when_missing == "create"
        )
        if will_create:
            for rel in _dirs_to_create(root, patch_op.target):
                created_dirs.add((patch_op.app_id, patch_op.location, rel))
        entry = _patch_one(steam_dir, root, patch_op, prev.get(key))
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
