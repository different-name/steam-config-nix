from dataclasses import dataclass, field
from pathlib import Path
from typing import Literal, Optional, Union


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
class Deletion:
    key_path: tuple[str, ...]
    guard_path: tuple[str, ...] = ()
    expected: Optional[str] = None


@dataclass
class ConfigPatch:
    file_path: Path
    file_format: Literal["keyvalues", "binary-keyvalues"]
    data: KeyValuesType
    close_steam: bool
    deletions: list[Deletion] = field(default_factory=list)


@dataclass
class UserManifest:
    compat_tools: dict[int, str] = field(default_factory=dict)
    launch_options: dict[int, str] = field(default_factory=dict)
    shortcuts: list[int] = field(default_factory=list)
