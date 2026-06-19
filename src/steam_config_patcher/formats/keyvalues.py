from typing import Iterator

from srctools import AtomicWriter, Keyvalues

from steam_config_patcher.steam import steam_is_closed
from steam_config_patcher.types import (
    ConfigPatch,
    Deletion,
    KeyValuesType,
    KeyValuesValue,
)

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


def overwrite_key(kv: Keyvalues, key_path: KeyPath, value: KeyValuesValue) -> bool:
    modified = False
    value = str(value)

    existing_blocks = list(kv.find_all(*key_path))

    if existing_blocks:
        for block in existing_blocks:
            if block.has_children():
                raise ValueError(
                    f"Refusing to overwrite non-leaf keyvalue block at {key_path}"
                )

            if block.value != value:
                block.value = value
                modified = True
    else:
        for i in range(len(key_path) - 1, 0, -1):
            parent_blocks = list(kv.find_all(*key_path[:i]))
            if not parent_blocks:
                continue

            for block in parent_blocks:
                block.set_key(key_path[i:], value)
                modified = True
            break

    return modified


def guard_matches(node: Keyvalues, deletion: Deletion) -> bool:
    if deletion.expected is None:
        return True

    target = node
    for key in deletion.guard_path:
        if not target.has_children() or key not in target:
            return False
        target = target.find_key(key)

    return not target.has_children() and target.value == deletion.expected


def delete_key(kv: Keyvalues, deletion: Deletion) -> bool:
    *parent_path, leaf_name = deletion.key_path

    modified = False
    for parent in list(kv.find_all(*parent_path)):
        if leaf_name not in parent:
            continue

        if not guard_matches(parent.find_key(leaf_name), deletion):
            continue

        del parent[leaf_name]
        modified = True

    return modified


def patch_keyvalues(config_patch: ConfigPatch) -> bool:
    if not config_patch.file_path.is_file():
        return True

    with config_patch.file_path.open(encoding="utf-8") as read_file:
        kv = Keyvalues.parse(read_file, config_patch.file_path)

    # update the kv object with the desired values, tracking if anything was modified
    # if we need to write changes, steam will need to be closed beforehand
    modified = False
    for key_path, value in list(iterate_leaves(config_patch.data)):
        if overwrite_key(kv, key_path, value):
            modified = True

    for deletion in config_patch.deletions:
        if delete_key(kv, deletion):
            modified = True

    if not modified:
        return True

    if not steam_is_closed(close_if_running=config_patch.close_steam):
        return False

    with AtomicWriter(config_patch.file_path, encoding="utf-8") as write_file:
        kv.serialise(write_file)

    return True
