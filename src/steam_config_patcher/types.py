from dataclasses import dataclass
from pathlib import Path
from typing import Literal, Union, Optional


@dataclass
class UserConfig:
    launch_options: dict[int, str]


@dataclass
class CompatToolConfig:
    name: str
    priority: int


@dataclass
class PatcherConfig:
    shutdown_behavior: Optional[str]
    restart_cmdline: list[str]
    steam_dir: Path
    compat_tool_mapping: dict[int, CompatToolConfig]
    users: dict[int, UserConfig]


NestedStrDict = dict[str, Union[str, "NestedStrDict"]]


@dataclass
class ConfigPatch:
    file_path: Path
    file_format: Literal["keyvalues"]
    data: NestedStrDict
    shutdown_behavior: Optional[str]
