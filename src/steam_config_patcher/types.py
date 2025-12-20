from dataclasses import dataclass
from pathlib import Path
from typing import Literal, Union


@dataclass
class UserConfig:
    launch_options: dict[int, str]


@dataclass
class CompatToolConfig:
    name: str
    priority: int


@dataclass
class PatcherConfig:
    close_steam: bool
    steam_dir: Path
    default_compat_tool: str
    compat_tool_mapping: dict[int, CompatToolConfig]
    users: dict[int, UserConfig]


NestedStrDict = dict[str, Union[str, "NestedStrDict"]]


@dataclass
class ConfigPatch:
    file_path: Path
    file_format: Literal["keyvalues"]
    data: NestedStrDict
    close_steam: bool
