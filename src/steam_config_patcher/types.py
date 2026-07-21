from dataclasses import dataclass, field
from pathlib import Path
from typing import Literal, Optional, Union

CONFIG_FILE = "config"
LOCALCONFIG_FILE = "localconfig"
APPMANIFEST_FILE_PREFIX = "appmanifest_"

APPMANIFEST_PATH = ("AppState",)
APPMANIFEST_USER_CONFIG_PATH = ("AppState", "UserConfig")
APPMANIFEST_BETA_KEY = "BetaKey"
APPMANIFEST_LANGUAGE_KEY = "language"
APPMANIFEST_AUTO_UPDATE_KEY = "AutoUpdateBehavior"

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


GRID_SLOTS = (
    ("cover", "{app_id}p"),
    ("header", "{app_id}"),
    ("hero", "{app_id}_hero"),
    ("logo", "{app_id}_logo"),
)


@dataclass
class GridArt:
    cover: Optional[str] = None
    header: Optional[str] = None
    hero: Optional[str] = None
    logo: Optional[str] = None


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
    game_betas: dict[int, str] = field(default_factory=dict)
    game_languages: dict[int, str] = field(default_factory=dict)
    game_update_behaviors: dict[int, str] = field(default_factory=dict)
    grid_art: dict[int, GridArt] = field(default_factory=dict)
    library_icon_apps: set[int] = field(default_factory=set)
    file_ops: list["FileOp"] = field(default_factory=list)
    remove_ops: list["RemoveOp"] = field(default_factory=list)


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
    grid_art: dict[str, str] = field(default_factory=dict)


FileLocation = Literal["install", "prefix"]


@dataclass
class ManagedFile:
    app_id: int
    location: FileLocation
    target: str
    op: Literal["place", "remove"]
    source_hash: Optional[str] = None
    had_backup: bool = False
    source_path: Optional[str] = None


@dataclass
class FileOp:
    app_id: int
    location: FileLocation
    target: str
    source: Path
    overwrite_changes: bool
    executable: Optional[bool] = None


@dataclass
class RemoveOp:
    app_id: int
    location: FileLocation
    target: str


@dataclass
class ManagedDir:
    app_id: int
    location: FileLocation
    target: str


@dataclass
class FilesManifest:
    files: list[ManagedFile] = field(default_factory=list)
    dirs: list[ManagedDir] = field(default_factory=list)
