from typing import Iterator

from steam_config_patcher.fileio import atomic_write_text
from steam_config_patcher.steam import steam_is_closed
from steam_config_patcher.types import (
    ConfigPatch,
    Deletion,
    KeyValuesType,
    KeyValuesValue,
)
from steam_config_patcher.vdf.text import VdfNode, dumps, loads

KeyPath = tuple[*tuple[str, ...], str]


def iterate_leaves(
    d: KeyValuesType, key_path: tuple[str, ...] = ()
) -> Iterator[tuple[KeyPath, KeyValuesValue]]:
    for k, v in d.items():
        new_path = key_path + (k,)
        if isinstance(v, dict):
            yield from iterate_leaves(v, new_path)
        else:
            yield new_path, v


def overwrite_key(kv: VdfNode, key_path: KeyPath, value: KeyValuesValue) -> bool:
    modified = False
    value = str(value)

    existing_nodes = list(kv.find_all(*key_path))

    if existing_nodes:
        for node in existing_nodes:
            if node.is_block:
                raise ValueError(
                    f"Refusing to overwrite non-leaf keyvalue block at {key_path}"
                )

            if node.value != value:
                node.value = value
                modified = True
    else:
        for i in range(len(key_path) - 1, 0, -1):
            parent_blocks = [b for b in kv.find_all(*key_path[:i]) if b.is_block]
            if not parent_blocks:
                continue

            for block in parent_blocks:
                block.set_path(key_path[i:], value)
                modified = True
            break

    return modified


def guard_matches(node: VdfNode, deletion: Deletion) -> bool:
    if deletion.expected is None:
        return True

    target = node
    for key in deletion.guard_path:
        if not target.is_block:
            return False
        target = target.find(key)
        if target is None:
            return False

    return not target.is_block and target.value == deletion.expected


def delete_key(kv: VdfNode, deletion: Deletion) -> bool:
    *parent_path, leaf_name = deletion.key_path
    parents = list(kv.find_all(*parent_path)) if parent_path else [kv]

    modified = False
    for parent in parents:
        target = parent.find(leaf_name)
        if target is None:
            continue

        if not guard_matches(target, deletion):
            continue

        if parent.remove(leaf_name):
            modified = True

    return modified


def patch_keyvalues(config_patch: ConfigPatch) -> bool:
    if not config_patch.file_path.is_file():
        return True

    kv = loads(config_patch.file_path.read_text(encoding="utf-8"))

    # update the kv object with the desired values, tracking if anything was modified
    # if we need to write changes, steam will need to be closed beforehand
    modified = False
    for key_path, value in iterate_leaves(config_patch.data):
        if overwrite_key(kv, key_path, value):
            modified = True

    for deletion in config_patch.deletions:
        if delete_key(kv, deletion):
            modified = True

    if not modified:
        return True

    if not steam_is_closed(close_if_running=config_patch.close_steam):
        return False

    atomic_write_text(config_patch.file_path, dumps(kv))
    return True
