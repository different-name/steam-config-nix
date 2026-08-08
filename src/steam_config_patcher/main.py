import argparse
import logging
from pathlib import Path
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

from steam_config_patcher.compat import resolve_compat_tool_name
from steam_config_patcher.patcher import patch_config_files
from steam_config_patcher.steam import get_steam_dir, get_steam_user_ids
from steam_config_patcher.types import (
    CompatToolConfig,
    FileOp,
    GridArt,
    NonSteamAppConfig,
    PatcherConfig,
    PatchOp,
    RemoveOp,
    UserConfig,
)


# reject unknown keys so a drift between the module's finalConfig and this
# schema fails loudly instead of being silently dropped
class StrictSchema(BaseModel):
    model_config = ConfigDict(extra="forbid")


class CompatToolRefSchema(StrictSchema):
    path: str


type CompatToolValue = str | CompatToolRefSchema | None


class ArtworkSchema(StrictSchema):
    cover: str | None = None
    header: str | None = None
    hero: str | None = None
    logo: str | None = None


class FileOpSchema(StrictSchema):
    location: Literal["game", "prefix"]
    target: str
    source: str
    mode: Literal["enforce", "seed", "lock"]
    executable: bool | None = None


class RemoveOpSchema(StrictSchema):
    location: Literal["game", "prefix"]
    target: str


class PatchOpSchema(StrictSchema):
    location: Literal["game", "prefix"]
    target: str
    format: Literal["ini", "json"]
    content: dict
    whenMissing: Literal["create", "skip"]


class AppSchema(StrictSchema):
    id: int
    launchOptions: str | None = None
    compatTool: CompatToolValue = None
    betaBranch: str | None = None
    language: str | None = None
    updateBehavior: str | None = None
    libraryIcon: bool = False
    artwork: ArtworkSchema = Field(default_factory=ArtworkSchema)
    files: list[FileOpSchema] = Field(default_factory=list)
    removeFiles: list[RemoveOpSchema] = Field(default_factory=list)
    patches: list[PatchOpSchema] = Field(default_factory=list)


class NonSteamAppSchema(AppSchema):
    name: str
    target: str
    startIn: str | None
    icon: str | None
    isHidden: bool
    allowOverlay: bool
    inVrLibrary: bool


class InputSchema(StrictSchema):
    onSteamRunning: Literal["wait", "close", "force-close", "skip"]
    defaultCompatTool: CompatToolValue
    displayRatesAsBits: bool | None = None
    apps: dict[str, AppSchema]
    nonSteamApps: dict[str, NonSteamAppSchema]


def resolve_compat_tool(compat_tool: CompatToolValue) -> str | None:
    if isinstance(compat_tool, CompatToolRefSchema):
        return resolve_compat_tool_name(Path(compat_tool.path))
    return compat_tool


logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")


def parse_input() -> PatcherConfig:
    parser = argparse.ArgumentParser(
        prog="steam-config-patcher",
        description="Patch local Steam config using JSON input",
    )
    parser.add_argument(
        "cfg_json",
        help="path to configuration JSON file to parse",
    )
    args = parser.parse_args()

    json_text = Path(args.cfg_json).read_text(encoding="utf-8")
    validated_input = InputSchema.model_validate_json(json_text)

    steam_dir = get_steam_dir()

    return PatcherConfig(
        on_steam_running=validated_input.onSteamRunning,
        steam_dir=steam_dir,
        display_rates_as_bits=validated_input.displayRatesAsBits,
        compat_tool_mapping={
            app.id: CompatToolConfig(
                name=name,
                priority=250 if app.id != 0 else 75,
            )
            for app in [
                *validated_input.apps.values(),
                *validated_input.nonSteamApps.values(),
                AppSchema(id=0, compatTool=validated_input.defaultCompatTool),
            ]
            if app.compatTool
            and (name := resolve_compat_tool(app.compatTool)) is not None
        },
        game_betas={
            app.id: app.betaBranch
            for app in validated_input.apps.values()
            if app.betaBranch
        },
        game_languages={
            app.id: app.language
            for app in validated_input.apps.values()
            if app.language
        },
        game_update_behaviors={
            app.id: app.updateBehavior
            for app in validated_input.apps.values()
            if app.updateBehavior
        },
        grid_art={
            app.id: GridArt(
                cover=app.artwork.cover,
                header=app.artwork.header,
                hero=app.artwork.hero,
                logo=app.artwork.logo,
            )
            for app in [
                *validated_input.apps.values(),
                *validated_input.nonSteamApps.values(),
            ]
            if any(
                (
                    app.artwork.cover,
                    app.artwork.header,
                    app.artwork.hero,
                    app.artwork.logo,
                )
            )
        },
        library_icon_apps={
            app.id for app in validated_input.apps.values() if app.libraryIcon
        },
        file_ops=[
            FileOp(
                app_id=app.id,
                location=op.location,
                target=op.target,
                source=Path(op.source),
                mode=op.mode,
                executable=op.executable,
            )
            for app in validated_input.apps.values()
            for op in app.files
        ],
        remove_ops=[
            RemoveOp(app_id=app.id, location=op.location, target=op.target)
            for app in validated_input.apps.values()
            for op in app.removeFiles
        ],
        patch_ops=[
            PatchOp(
                app_id=app.id,
                location=op.location,
                target=op.target,
                format=op.format,
                content=op.content,
                when_missing=op.whenMissing,
            )
            for app in validated_input.apps.values()
            for op in app.patches
        ],
        users={
            user_id: UserConfig(
                launch_options={
                    app.id: app.launchOptions
                    for app in validated_input.apps.values()
                    if app.launchOptions
                },
                non_steam_apps={
                    app.id: NonSteamAppConfig(
                        name=app.name,
                        target=app.target,
                        start_in=app.startIn or "",
                        icon=app.icon or "",
                        launch_options=app.launchOptions or "",
                        is_hidden=app.isHidden,
                        allow_desktop_config=True,
                        allow_overlay=app.allowOverlay,
                        in_vr_library=app.inVrLibrary,
                    )
                    for app in validated_input.nonSteamApps.values()
                },
            )
            for user_id in get_steam_user_ids(steam_dir)
        },
    )


def main() -> None:
    cfg = parse_input()

    patch_config_files(cfg)


if __name__ == "__main__":
    main()
