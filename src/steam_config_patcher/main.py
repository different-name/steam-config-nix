import argparse
from itertools import chain
import logging
from typing import Optional

from pydantic import BaseModel, Field
from srctools import steam

from steam_config_patcher.patcher import patch_config_files
from steam_config_patcher.steam import get_steam_user_ids
from steam_config_patcher.types import CompatToolConfig, PatcherConfig, UserConfig


class AppSchema(BaseModel):
    id: int
    launchOptions: Optional[str] = None
    wrapperPath: Optional[str] = None
    compatTool: Optional[str] = None


class UserAppSchema(BaseModel):
    id: int
    launchOptions: Optional[str] = None
    wrapperPath: Optional[str] = None


class UserSchema(BaseModel):
    id: int
    apps: dict[str, UserAppSchema] = Field(default_factory=dict)


class InputSchema(BaseModel):
    shutdownBehavior: Optional[str | list[str]]
    restartCmdline: list[str]
    defaultCompatTool: Optional[str]
    apps: dict[str, AppSchema]
    users: dict[str, UserSchema]


logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")


def parse_input() -> PatcherConfig:
    parser = argparse.ArgumentParser(
        prog="steam-config-patcher",
        description="Patch local Steam config using JSON input",
    )
    parser.add_argument(
        "cfg_json",
        help="configuration JSON to parse",
    )
    args = parser.parse_args()

    validated_input = InputSchema.model_validate_json(args.cfg_json)

    steam_dir = steam.get_steam_install_path()

    return PatcherConfig(
        shutdown_behavior=validated_input.shutdownBehavior if type(validated_input.shutdownBehavior) != list else "restart",
        restart_cmdline=validated_input.restartCmdline,
        steam_dir=steam_dir,
        compat_tool_mapping={
            app.id: CompatToolConfig(
                name=app.compatTool, priority=250 if app.id != 0 else 75
            )
            for app in [
                *validated_input.apps.values(),
                AppSchema(id=0, compatTool=validated_input.defaultCompatTool),
            ]
            if app.compatTool
        },
        users={
            user_id: UserConfig(
                launch_options={
                    app.id: f"{app.wrapperPath} %command%"
                    for app in chain(
                        validated_input.apps.values(),
                        *(
                            u.apps.values()
                            for u in validated_input.users.values()
                            if u.id == user_id
                        ),
                    )
                    if app.wrapperPath
                }
            )
            for user_id in get_steam_user_ids(steam_dir)
        },
    )


def main() -> None:
    cfg = parse_input()

    patch_config_files(cfg)


if __name__ == "__main__":
    main()
