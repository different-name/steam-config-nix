from pathlib import Path
import time

import psutil

from typing import Callable, Optional
import subprocess


def get_steam_user_ids(steam_dir: Path) -> list[int]:
    return [
        int(p.name)
        for p in (steam_dir / "userdata").iterdir()
        if p.is_dir() and p.name.isdigit() and p.name != "0"
    ]

def steam_is_closed(close_if_running=False) -> tuple[bool, Callable]:

    steam_cmdline: Optional[list[str]] = None

    closed = True
    for proc in psutil.process_iter(["name"]):
        if proc.name() == "steam":
    
            steam_cmdline = proc.cmdline()[2:] or []

            closed = False
            if close_if_running:
                proc.terminate()
                try:
                    proc.wait(timeout=30)
                except psutil.TimeoutExpired:
                    proc.kill()
                time.sleep(2)
                closed = True

    def restart(restart_cmdline): 
        if not closed or steam_cmdline == None:
            return
 
        subprocess.Popen(args=restart_cmdline+steam_cmdline)

    return closed, restart
