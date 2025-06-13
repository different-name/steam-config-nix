import json
import os
import sys
from pathlib import Path
from typing import Union
import logging
from srctools import Keyvalues

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')


def load_json_config(path: Path) -> dict[str, str]:
    """
    Load and validate launch options from a JSON file.

    Expected format:
        {
            "<app_id>": "<launch_options_string>",
            ...
        }
    """
    # parse json file
    with path.open('r', encoding='utf-8') as f:
        data = json.load(f)

    # verify provided file is a json object
    if not isinstance(data, dict):
        raise ValueError("JSON root must be an object/dictionary.")

    # verify that the json object only contains key value pairs of string: string
    for app_id, options in data.items():
        if not isinstance(app_id, str):
            raise ValueError(f"App ID keys must be strings, got {type(app_id)}: {app_id}")
        if not isinstance(options, str):
            raise ValueError(f"Launch options must be strings for app '{app_id}', got {type(options)}")

    return data


def get_or_create_block(parent: Keyvalues, key_name: str) -> Keyvalues:
    """Find a sub-block with the given name, or create one if missing."""
    try:
        return parent.find_key(key_name)
    except KeyError:
        new_block = Keyvalues(key_name, [])
        parent.value.append(new_block)
        return new_block


def get_or_create_nested_block(root: Keyvalues, keys: list[str]) -> Keyvalues:
    """Traverse and create nested blocks based on the list of keys."""
    block = root
    for key in keys:
        block = block.ensure_exists(key)
    return block


def remove_key_all(block: Keyvalues, key_name: str) -> None:
    """Remove all occurrences of a key with the given name from the Keyvalues block."""
    while True:
        try:
            block.__delitem__(key_name)
        except IndexError:
            break


def set_launch_options(localconfig_path: Path, launch_options: dict[str, Union[str, dict, list]]) -> None:
    """Update launch options for apps in the given localconfig.vdf file."""
    # parse the localconfig.vdf file's current content
    try:
        with localconfig_path.open('r', encoding='utf-8') as f:
            root = Keyvalues.parse(f)
    except Exception as e:
        logging.error(f"Failed to parse VDF file '{localconfig_path}': {e}")
        return

    # fetch the apps block, this is where launch options for each app are stored
    apps = get_or_create_nested_block(root, ['UserLocalConfigStore', 'Software', 'Valve', 'Steam', 'Apps'])

    # for each desired launch option, update or create the corresponding app block
    for app_id, options in launch_options.items():
        app_block = apps.ensure_exists(app_id)
        # remove existing LaunchOptions keys
        remove_key_all(app_block, 'LaunchOptions')
        # append desired launch options
        app_block.set_key('LaunchOptions', options)

    # write changes
    try:
        with localconfig_path.open('w', encoding='utf-8') as f:
            root.serialise(f)
    except Exception as e:
        logging.error(f"Failed to write VDF file '{localconfig_path}': {e}")
        return

    logging.info(f"Updated launch options in {localconfig_path}")


def get_all_localconfig_paths(steam_config_dir: Path) -> list[Path]:
    """Find all localconfig.vdf files in user directories under the given Steam config path."""
    user_dirs = steam_config_dir.glob('userdata/*/config')
    return [p / 'localconfig.vdf' for p in user_dirs if (p / 'localconfig.vdf').exists()]


def main() -> None:
    import argparse

    # set up arguments
    parser = argparse.ArgumentParser(description="Update Steam launch options in localconfig.vdf files.")
    parser.add_argument('json_path', type=Path, help='Path to the JSON file containing launch options.')
    args = parser.parse_args()

    # parse desired launch options
    if not args.json_path.exists():
        logging.error(f"JSON file not found: {args.json_path}")
        sys.exit(1)
    launch_options = load_json_config(args.json_path)

    # locate steam config directory
    home = Path(os.getenv("HOME", ""))
    xdg_data_home = Path(os.getenv("XDG_DATA_HOME", ""))
    steam_paths = [
        home / ".steam/steam/config",
        xdg_data_home / "Steam/config"
    ]
    steam_path = next((p for p in steam_paths if p.exists()), None)

    # locate all localconfig.vdf files
    if steam_path is None:
        logging.error("Could not locate Steam config directory.")
        sys.exit(1)
    localconfig_paths = get_all_localconfig_paths(steam_path.parent)

    # update localconfig files with desired launch options
    if not localconfig_paths:
        logging.warning("No localconfig.vdf files found.")
        sys.exit(0)
    for path in localconfig_paths:
        logging.info(f"Updating {path}")
        set_launch_options(path, launch_options)


if __name__ == '__main__':
    main()
