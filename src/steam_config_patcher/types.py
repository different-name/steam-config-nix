from dataclasses import dataclass, field
from pathlib import Path
from typing import Literal

CONFIG_FILE = "config"
LOCALCONFIG_FILE = "localconfig"
DISPLAY_RATES_AS_BITS_PATH = (
    "UserLocalConfigStore",
    "system",
    "displayratesasbits",
)
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
    cover: str | None = None
    header: str | None = None
    hero: str | None = None
    logo: str | None = None


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
    display_rates_as_bits: bool | None = None
    game_betas: dict[int, str] = field(default_factory=dict)
    game_languages: dict[int, str] = field(default_factory=dict)
    game_update_behaviors: dict[int, str] = field(default_factory=dict)
    grid_art: dict[int, GridArt] = field(default_factory=dict)
    library_icon_apps: set[int] = field(default_factory=set)
    file_ops: list["FileOp"] = field(default_factory=list)
    remove_ops: list["RemoveOp"] = field(default_factory=list)
    patch_ops: list["PatchOp"] = field(default_factory=list)


type KeyValuesValue = str | int
type KeyValuesType = dict[str, KeyValuesValue | KeyValuesType]


@dataclass
class Deletion:
    key_path: tuple[str, ...]
    guard_path: tuple[str, ...] = ()
    expected: str | None = None


@dataclass(frozen=True)
class ManagedKey:
    file: str
    key_path: tuple[str, ...]
    guard_path: tuple[str, ...] = ()
    expected: str | None = None

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


type FileLocation = Literal["game", "prefix"]


@dataclass
class ManagedFile:
    app_id: int
    location: FileLocation
    target: str
    op: Literal["place", "remove", "patch"]
    source_hash: str | None = None
    had_backup: bool = False
    source_path: str | None = None


@dataclass
class FileOp:
    app_id: int
    location: FileLocation
    target: str
    source: Path
    mode: Literal["enforce", "seed", "lock"]
    executable: bool | None = None


@dataclass
class RemoveOp:
    app_id: int
    location: FileLocation
    target: str


@dataclass
class PatchOp:
    app_id: int
    location: FileLocation
    target: str
    format: Literal["ini", "json", "registry", "keyvalue", "unityPrefs"]
    content: dict
    create_if_missing: bool


@dataclass
class ManagedDir:
    app_id: int
    location: FileLocation
    target: str


@dataclass
class FilesManifest:
    files: list[ManagedFile] = field(default_factory=list)
    dirs: list[ManagedDir] = field(default_factory=list)
