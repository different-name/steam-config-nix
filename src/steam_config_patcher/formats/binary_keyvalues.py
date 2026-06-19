from copy import deepcopy
from typing import Any

import vdf

from steam_config_patcher.steam import steam_is_closed
from steam_config_patcher.types import ConfigPatch, Deletion


def delete_key(destination: dict[Any, Any], deletion: Deletion) -> bool:
    *parent_path, leaf_key = deletion.key_path

    node = destination
    for key in parent_path:
        if not isinstance(node, dict) or key not in node:
            return False
        node = node[key]

    if not isinstance(node, dict) or leaf_key not in node:
        return False

    del node[leaf_key]
    return True


def recursive_update(destination: dict[Any, Any], source: dict[Any, Any]) -> bool:
    modified = False
    for source_key, source_value in source.items():
        if source_key in destination:
            destination_value = destination[source_key]
            if isinstance(destination_value, dict) and isinstance(source_value, dict):
                if recursive_update(destination_value, source_value):
                    modified = True
            else:
                if destination_value != source_value:
                    destination[source_key] = deepcopy(source_value)
                    modified = True
        else:
            destination[source_key] = deepcopy(source_value)
            modified = True
    return modified


def patch_binary_keyvalues(config_patch: ConfigPatch) -> bool:
    if not config_patch.file_path.is_file():
        return True

    with config_patch.file_path.open(mode="rb") as read_file:
        kv = vdf.binary_load(read_file)

    modified = recursive_update(kv, config_patch.data)

    for deletion in config_patch.deletions:
        if delete_key(kv, deletion):
            modified = True

    if not modified:
        return True

    if not steam_is_closed(close_if_running=config_patch.close_steam):
        return False

    with config_patch.file_path.open(mode="wb") as write_file:
        vdf.binary_dump(kv, write_file)

    return True
