from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Optional
import time

import psutil
import subprocess
import os


def get_steam_user_ids(steam_dir: Path) -> list[int]:
    return [
        int(p.name)
        for p in (steam_dir / "userdata").iterdir()
        if p.is_dir() and p.name.isdigit() and p.name != "0"
    ]


def steam_is_closed(close_if_running=False) -> tuple[bool, Callable]:
    closed = True

    @dataclass
    class Process:
        cmdline: list[str]
        environ: dict[str, str]
        cwd: Path

    steam_process: Optional[Proccess] = None
    for proc in psutil.process_iter(["name"]):
        if proc.name() == "steam":
            closed = False
            steam_process = Process(
                cmdline=proc.cmdline(),
                environ=proc.environ(),
                cwd=proc.cwd()
            )
            if close_if_running:
                proc.terminate()
                try:
                    proc.wait(timeout=30)
                except psutil.TimeoutExpired:
                    proc.kill()
                time.sleep(2)
                closed = True

    def restart(steam_config): 
        if not closed or steam_process == None:
            return
        
        env = os.environ.copy()

        subprocess.Popen(
            # Passing the old Steam's cmdline will over time (at least for me) duplicate the argument "-srt-logger-opened" as Steam always seems to add that argument itself.
            # We could probably solve this by removing all duplicates from the args. This would require more logic as there are arguments for Steam that consist of two elements, e.g. -language <language>. Steam however doesn't seem to complain about duplicate arguments.
            args=steam_config.launch_prefix+[steam_config.restart_exe]+(steam_process.cmdline[1:])+steam_config.restart_args, 
            cwd=steam_process.cwd, 
            # For some reason Steam doesn't seem to start when I just pass it its old environ. Maybe a bit hacky of a solution.
            env=(env.update(steam_process.environ))
        )

        return

    return closed, restart

