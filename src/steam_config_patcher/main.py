import argparse
import logging
from pathlib import Path
from typing import Optional

from pydantic import BaseModel
from srctools import steam

from steam_config_patcher.patcher import patch_config_files
from steam_config_patcher.steam import get_steam_user_ids
from steam_config_patcher.types import (
    CompatToolConfig,
    NonSteamAppConfig,
    PatcherConfig,
    UserConfig,
)


class AppSchema(BaseModel):
    id: int
    launchOptions: Optional[str] = None
    compatTool: Optional[str] = None


class NonSteamAppSchema(AppSchema):
    name: str
    target: str
    startIn: Optional[str]
    icon: Optional[str]
    isHidden: bool
    allowOverlay: bool
    inVrLibrary: bool


class InputSchema(BaseModel):
    closeSteam: bool
    defaultCompatTool: Optional[str]
    apps: dict[str, AppSchema]
    nonSteamApps: dict[str, NonSteamAppSchema]


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

    steam_dir = steam.get_steam_install_path()

    return PatcherConfig(
        close_steam=validated_input.closeSteam,
        steam_dir=steam_dir,
        compat_tool_mapping={
            app.id: CompatToolConfig(
                name=app.compatTool, priority=250 if app.id != 0 else 75
            )
            for app in [
                *validated_input.apps.values(),
                *validated_input.nonSteamApps.values(),
                AppSchema(id=0, compatTool=validated_input.defaultCompatTool),
            ]
            if app.compatTool
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
