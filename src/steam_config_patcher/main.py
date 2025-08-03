import argparse
import json
import re
import glob
import copy
from deepmerge import always_merger
from pathlib import Path
from srctools import Keyvalues, AtomicWriter
from typing import Union, Tuple, Dict, Any
import psutil
import shutil
from tempfile import NamedTemporaryFile
import logging


logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')


def parse_args():
    parser = argparse.ArgumentParser(
        prog="steam-config-patcher",
        description="Patch Steam vdf files using JSON input"
    )
    parser.add_argument(
        "--json",
        dest="json_input",
        required=True,
        help="path to the JSON input file to parse"
    )
    parser.add_argument(
        "--close-steam",
        action="store_true",
        help="close Steam before writing any changes"
    )
    return parser.parse_args()


def load_json(json_input: str) -> Dict[Path, Dict[str, Any]]:
    try:
        data = json.loads(json_input)
        if not isinstance(data, dict):
            raise ValueError(f"JSON input is not a valid object")

        final_data: Dict[Path, Dict[str, Any]] = {}
        exact_paths: Dict[Path, Dict[str, Any]] = {}

        for path_str, config in data.items():
            if bool(re.search(r'[\*\?\[\]]', path_str)):
                for resolved_path_str in glob.glob(path_str):
                    final_data[Path(resolved_path_str)] = copy.deepcopy(config)
            else:
                exact_paths[Path(path_str)] = config

        for path, config in exact_paths.items():
            if path in final_data:
                always_merger.merge(final_data[path], config)
            else:
                final_data[path] = config
        
        return final_data
    except Exception as e:
        raise ValueError(f"Failed to parse json input: {e}") 


def load_vdf(path: Path) -> Keyvalues:
    try:
        with open(path) as vdf_f:
            return Keyvalues.parse(vdf_f)
    except Exception as e:
        raise ValueError(f"Failed to parse VDF file '{path}': {e}")


def overwrite_key(root: Keyvalues, path: Tuple[str, ...], value: str) -> bool:
    if len(path) > 1:
        parent_path = path[:-1]
        leaf_key = path[-1]
        parent_blocks = list(root.find_all(*parent_path))
    else:
        leaf_key = path[0]
        parent_blocks = [root]

    deleted_values = False
    set_value = True

    for block in parent_blocks:
        for leaf in block.find_all(leaf_key):
            if leaf.has_children():
                raise RuntimeError(f"Refusing to overwrite Block keyvalue: {path}")
            if leaf.value == value:
                set_value = False
            else:
                block.value.remove(leaf)
                deleted_values = True

    if set_value:
        block = root
        for key in parent_path:
            block = block.ensure_exists(key)
        block.set_key(leaf_key, value)

    return deleted_values or set_value


def overwrite_keys(root: Keyvalues, obj: Dict[str, Any]) -> bool:
    def _recurse(data: Union[Dict[str, Any], str], path: Tuple[str, ...]) -> bool:
        if isinstance(data, dict):
            modified_values = False
            for key, value in data.items():
                modified_values = _recurse(value, path + (key,)) or modified_values
            return modified_values
        elif isinstance(data, str):
            return overwrite_key(root, path, data)
        else:
            raise RuntimeError(f"Value is not a string {path}: {data}")

    return _recurse(obj, ())


def ensure_steam_closed(should_close: bool) -> bool:
    closed = True
    for proc in psutil.process_iter(['name']):
        if proc.name() == 'steam':
            closed = False
            if should_close:
                logging.info("Closing Steam")
                proc.terminate()
                try:
                    proc.wait(timeout=30)
                except psutil.TimeoutExpired:
                    proc.kill()
                closed = True
    return closed


def write_vdf(path: Path, root: Keyvalues) -> None:
    try:
        backup_path = path.with_suffix(path.suffix + '.bak')
        shutil.copy(path, backup_path)
        logging.info(f"Backup written to {backup_path}")

        with AtomicWriter(path) as f:
            root.serialise(f)
    except Exception as e:
        raise IOError(f"Failed to write to '{path}': {e}")
            

def main() -> None:
    args = parse_args()
    json_data = load_json(args.json_input)

    to_write = []
    for vdf_path_str, data in json_data.items():
        if not isinstance(data, dict):
            raise ValueError(f"{vdf_path_str} is not a valid JSON object")

        vdf_path = Path(vdf_path_str)
        if not vdf_path.exists():
            logging.warning(f"VDF file \"{vdf_path}\" not found, skipping")
            continue
        vdf_root = load_vdf(vdf_path)

        modified_values = overwrite_keys(vdf_root, data)
        if modified_values:
            to_write.append((vdf_path, vdf_root))
        else:
            logging.info(f"\"{vdf_path}\" is up to date, skipping write")

    if not to_write:
        return

    if not ensure_steam_closed(args.close_steam):
        logging.warning("Steam is currently running, close steam or use --close-steam")
        return

    for vdf_path, vdf_root in to_write:
        logging.info(f"Writing changes to \"{vdf_path}\"")
        write_vdf(vdf_path, vdf_root)
    

if __name__ == '__main__':
    main()
