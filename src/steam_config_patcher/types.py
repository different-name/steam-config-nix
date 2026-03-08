from dataclasses import dataclass
from pathlib import Path
from typing import Literal, Union


@dataclass
class NonSteamAppConfig:
    name: str
    target: str
    start_in: str
    icon: str
    launch_options: str
    is_hidden: bool
    allow_desktop_config: bool
    allow_overlay: bool
    in_vr_library: bool


@dataclass
class UserConfig:
    launch_options: dict[int, str]
    non_steam_apps: dict[int, NonSteamAppConfig]


@dataclass
class CompatToolConfig:
    name: str
    priority: int


@dataclass
class PatcherConfig:
    close_steam: bool
    steam_dir: Path
    compat_tool_mapping: dict[int, CompatToolConfig]
    users: dict[int, UserConfig]


KeyValuesValue = str | int
KeyValuesType = dict[str, Union[KeyValuesValue, "KeyValuesType"]]


@dataclass
class ConfigPatch:
    file_path: Path
    file_format: Literal["keyvalues", "binary-keyvalues"]
    data: KeyValuesType
    close_steam: bool
