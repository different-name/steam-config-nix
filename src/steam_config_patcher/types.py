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
class SteamConfig:
    dir: Path
    auto_close: bool
    auto_restart: bool
    restart_args: list[str]
    restart_exe: str
    launch_prefix: list[str]


@dataclass
class PatcherConfig:
    steam_config: SteamConfig
    compat_tool_mapping: dict[int, CompatToolConfig]
    users: dict[int, UserConfig]


NestedStrDict = dict[str, Union[str, "NestedStrDict"]]


@dataclass
class ConfigPatch:
    steam_config: SteamConfig
    file_path: Path
    file_format: Literal["keyvalues"]
    data: NestedStrDict
