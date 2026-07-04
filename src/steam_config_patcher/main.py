import argparse
import logging
from pathlib import Path
from typing import Literal, Optional, Union

from pydantic import BaseModel, ConfigDict, Field

from steam_config_patcher.compat import resolve_compat_tool_name
from steam_config_patcher.patcher import patch_config_files
from steam_config_patcher.steam import get_steam_dir, get_steam_user_ids
from steam_config_patcher.types import (
    CompatToolConfig,
    GridArt,
    NonSteamAppConfig,
    PatcherConfig,
    UserConfig,
)


# reject unknown keys so a drift between the module's finalConfig and this
# schema fails loudly instead of being silently dropped
class StrictSchema(BaseModel):
    model_config = ConfigDict(extra="forbid")


class CompatToolRefSchema(StrictSchema):
    path: str


CompatToolValue = Optional[Union[str, CompatToolRefSchema]]


class ArtworkSchema(StrictSchema):
    cover: Optional[str] = None
    header: Optional[str] = None
    hero: Optional[str] = None
    logo: Optional[str] = None


class AppSchema(StrictSchema):
    id: int
    launchOptions: Optional[str] = None
    compatTool: CompatToolValue = None
    betaBranch: Optional[str] = None
    language: Optional[str] = None
    artwork: ArtworkSchema = Field(default_factory=ArtworkSchema)


class NonSteamAppSchema(AppSchema):
    name: str
    target: str
    startIn: Optional[str]
    icon: Optional[str]
    isHidden: bool
    allowOverlay: bool
    inVrLibrary: bool


class InputSchema(StrictSchema):
    onSteamRunning: Literal["wait", "close", "force-close", "skip"]
    defaultCompatTool: CompatToolValue
    apps: dict[str, AppSchema]
    nonSteamApps: dict[str, NonSteamAppSchema]


def resolve_compat_tool(compat_tool: CompatToolValue) -> Optional[str]:
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
        compat_tool_mapping={
            app.id: CompatToolConfig(
                name=resolve_compat_tool(app.compatTool),
                priority=250 if app.id != 0 else 75,
            )
            for app in [
                *validated_input.apps.values(),
                *validated_input.nonSteamApps.values(),
                AppSchema(id=0, compatTool=validated_input.defaultCompatTool),
            ]
            if app.compatTool
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
