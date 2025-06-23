import json
import os
from pathlib import Path
from typing import Optional
import logging
import argparse
from tempfile import NamedTemporaryFile
import shutil

import psutil
from srctools import Keyvalues, NoKeyError

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
    if not path.exists():
        raise FileNotFoundError(f"JSON file not found: {path}")

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

    logging.info(f"Loaded launch options for {len(data)} apps from {path}")
    return data


def get_localconfig_paths() -> list[Path]:
    """Find all localconfig.vdf files in user directories."""
    home = Path(os.getenv("HOME", ""))
    xdg_data_home = Path(os.getenv("XDG_DATA_HOME", home / ".local/share"))
    steam_config_paths = [
        home / ".steam/steam/config",
        xdg_data_home / "Steam/config"
    ]

    steam_config_path = next((p for p in steam_config_paths if p.exists()), None)
    if steam_config_path is None:
        raise FileNotFoundError("Could not locate Steam config directory.")

    user_dirs = steam_config_path.parent.glob('userdata/*/config')
    localconfig_paths = [p / 'localconfig.vdf' for p in user_dirs if (p / 'localconfig.vdf').exists()]
    if not localconfig_paths:
        raise FileNotFoundError("No localconfig.vdf files found.")
    return localconfig_paths


def get_or_create_nested_block(root: Keyvalues, keys: list[str]) -> Keyvalues:
    """Traverse and create nested blocks based on the list of keys."""
    block = root
    for key in keys:
        block = block.ensure_exists(key)
    return block


def read_localconfig(localconfig_path: Path) -> Keyvalues:
    """Parse the localconfig.vdf file into a Keyvalues tree."""
    logging.info(f"Reading {localconfig_path}")
    try:
        with localconfig_path.open('r', encoding='utf-8') as f:
            root = Keyvalues.parse(f)
            return root
    except Exception as e:
        raise ValueError(f"Failed to parse VDF file '{localconfig_path}': {e}")

def write_localconfig(localconfig_path: Path, kv: Keyvalues) -> None:
    """Write the Keyvalues tree to the file."""
    try:
        # create backup
        backup_path = localconfig_path.with_suffix(localconfig_path.suffix + '.bak')
        shutil.copy(localconfig_path, backup_path)
        logging.info(f"Backup created at {backup_path}")

        # write config to temporary file, then overwrite config
        with NamedTemporaryFile('w', delete=False, encoding='utf-8') as tmp_file:
            kv.serialise(tmp_file)
        shutil.move(tmp_file.name, localconfig_path)
    except Exception as e:
        raise IOError(f"Failed to write VDF file '{localconfig_path}': {e}")
    logging.info(f"Updated launch options in {localconfig_path}")


def generate_updated_vdf(existing: Keyvalues, launch_options: dict[str, str]) -> Optional[Keyvalues]:
    """Return a new Keyvalues object with updated launch options."""
    # fetch the apps block, this is where launch options for each app are stored
    root = existing.copy()
    apps = get_or_create_nested_block(root, ['UserLocalConfigStore', 'Software', 'Valve', 'Steam', 'Apps'])

    config_modified = False

    # for each desired launch option, update or create the corresponding app block
    for app_id, options in launch_options.items():
        app_block = apps.ensure_exists(app_id)

        # check if desired value exists
        try:
            current_value = app_block.find_key('LaunchOptions').value
        except NoKeyError:
            current_value = None

        if current_value != options:
            logging.info(f"Updating launch options for app {app_id}")
            
            config_modified = True
            # remove existing LaunchOptions keys
            while 'LaunchOptions' in app_block:
                del app_block['LaunchOptions']
            # append desired launch options
            app_block.set_key('LaunchOptions', options)

    if config_modified:
        return root
    else:
        return None


def is_steam_running() -> bool:
    """Check if Steam is currently running."""
    return any(proc.name() == 'steam' for proc in psutil.process_iter(['name']))


def stop_steam() -> None:
    """Gently terminate the Steam process and wait for it to exit."""
    for proc in psutil.process_iter(['name']):
        if proc.name() == 'steam':
            logging.info(f"Stopping Steam process (PID {proc.pid})...")
            try:
                proc.terminate()
                try:
                    proc.wait(timeout=30)
                    logging.info("Steam has exited.")
                except psutil.TimeoutExpired:
                    logging.warning("Steam did not shut down within 30 seconds. Forcing termination.")
                    proc.kill()
            except Exception as e:
                raise RuntimeError(f"Failed to terminate Steam process (PID {proc.pid}): {e}") from e


def main() -> None:
    # set up arguments
    parser = argparse.ArgumentParser(description="Update Steam launch options in localconfig.vdf files.")
    parser.add_argument('json_path', type=Path,
        help='Path to the JSON file containing launch options.')
    parser.add_argument('-f', '--force', action='store_true',
        help='Automatically close steam if it is running when modifying config.')
    args = parser.parse_args()

    # handle steam state
    steam_running = is_steam_running()
    if steam_running and not args.force:
        logging.warning("Steam is currently running, will not apply configuration. Use -f to automatically stop steam.")
        return

    # parse desired launch options
    launch_options = load_json_config(args.json_path)

    # locate all localconfig.vdf files
    localconfig_paths = get_localconfig_paths()

    # update localconfig files with desired launch options
    to_write = []
    for path in localconfig_paths:
        localconfig = read_localconfig(path)
        updated_localconfig = generate_updated_vdf(localconfig, launch_options)
        if updated_localconfig:
            to_write.append((path, updated_localconfig))
            
    if to_write:
        if steam_running:
            stop_steam()
            
        for path, updated_localconfig in to_write:
            write_localconfig(path, updated_localconfig)
        logging.info(f"Updated {len(to_write)} localconfig.vdf file(s).")
    else:
        logging.info("No changes were necessary.")
    

if __name__ == '__main__':
    main()
