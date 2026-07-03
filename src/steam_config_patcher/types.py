from dataclasses import dataclass, field
from pathlib import Path
from typing import Literal, Optional, Union

CONFIG_FILE = "config"
LOCALCONFIG_FILE = "localconfig"

COMPAT_TOOL_MAPPING_PATH = (
    "InstallConfigStore",
    "Software",
    "Valve",
    "Steam",
    "CompatToolMapping",
)
LOCALCONFIG_APPS_PATH = ("UserLocalConfigStore", "Software", "Valve", "Steam", "Apps")


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
    on_steam_running: Literal["wait", "close", "force-close", "skip"]
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


@dataclass(frozen=True)
class ManagedKey:
    file: str
    key_path: tuple[str, ...]
    guard_path: tuple[str, ...] = ()
    expected: Optional[str] = None

    def to_deletion(self) -> Deletion:
        return Deletion(
            key_path=self.key_path,
            guard_path=self.guard_path,
            expected=self.expected,
        )


@dataclass
class ConfigPatch:
    file_path: Path
    file_format: Literal["keyvalues", "binary-keyvalues"]
    data: KeyValuesType
    deletions: list[Deletion] = field(default_factory=list)


@dataclass
class UserManifest:
    managed_keys: list[ManagedKey] = field(default_factory=list)
    shortcuts: list[int] = field(default_factory=list)
