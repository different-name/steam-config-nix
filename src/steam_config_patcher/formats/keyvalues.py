from typing import Iterator

from srctools import AtomicWriter, Keyvalues

from steam_config_patcher.steam import steam_is_closed
from steam_config_patcher.types import ConfigPatch, NestedStrDict

from typing import Optional, Callable

KeyPath = tuple[*tuple[str, ...], str]


def iterate_leaves(
    d: NestedStrDict, key_path: tuple[str, ...] = ()
) -> Iterator[tuple[KeyPath, str]]:
    for k, v in d.items():
        new_path = key_path + (k,)
        if isinstance(v, dict):
            yield from iterate_leaves(v, new_path)
        else:
            yield new_path, v


def overwrite_key(kv: Keyvalues, key_path: KeyPath, value: str) -> bool:
    modified = False

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


def patch_keyvalues(config_patch: ConfigPatch) -> Optional[Callable]:
    if not config_patch.file_path.is_file():
        return

    with config_patch.file_path.open(encoding="utf-8") as read_file:
        kv = Keyvalues.parse(read_file, config_patch.file_path)

    # update the kv object with the desired values, tracking if anything was modified
    # if we need to write changes, steam will need to be closed beforehand
    modified = any(
        [
            overwrite_key(kv, key_path, value)
            for key_path, value in list(iterate_leaves(config_patch.data))
        ]
    )
 
    if modified:
        is_closed, restart_steam = steam_is_closed(close_if_running=(config_patch.shutdown_behavior != None))

        if is_closed:
            with AtomicWriter(config_patch.file_path, encoding="utf-8") as write_file:
                kv.serialise(write_file)
            if config_patch.shutdown_behavior != "close":
                return restart_steam

    return None
