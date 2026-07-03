import os
import shutil
import subprocess
import time
from pathlib import Path

import psutil

SHUTDOWN_TIMEOUT = 30


def get_steam_dir() -> Path:
    home = Path.home()
    candidates = [
        home / ".steam" / "root",
        home / ".steam" / "steam",
        home / ".local" / "share" / "Steam",
    ]

    for candidate in candidates:
        if candidate.is_dir():
            return candidate.resolve()

    raise FileNotFoundError("could not locate a Steam installation")


def get_steam_user_ids(steam_dir: Path) -> list[int]:
    return [
        int(p.name)
        for p in (steam_dir / "userdata").iterdir()
        if p.is_dir() and p.name.isdigit() and p.name != "0"
    ]


def steam_processes() -> list[psutil.Process]:
    uid = os.getuid()
    processes = []
    for proc in psutil.process_iter(["name"]):
        try:
            if proc.info["name"] == "steam" and proc.uids().real == uid:
                processes.append(proc)
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
    return processes


def steam_is_running() -> bool:
    return bool(steam_processes())


def game_processes() -> list[psutil.Process]:
    uid = os.getuid()
    processes = []
    for proc in psutil.process_iter(["name", "cmdline"]):
        try:
            if proc.info["name"] != "reaper" or proc.uids().real != uid:
                continue
            if "SteamLaunch" in (proc.info["cmdline"] or []):
                processes.append(proc)
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
    return processes


def game_is_running() -> bool:
    return bool(game_processes())


def wait_for_game_exit() -> None:
    while True:
        processes = game_processes()
        if not processes:
            break
        psutil.wait_procs(processes)


def wait_for_steam_exit() -> None:
    while True:
        processes = steam_processes()
        if not processes:
            break
        psutil.wait_procs(processes)

    time.sleep(2)


def close_steam() -> None:
    processes = steam_processes()
    if not processes:
        return

    steam_bin = shutil.which("steam")
    if steam_bin:
        try:
            subprocess.run(
                [steam_bin, "-shutdown"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=SHUTDOWN_TIMEOUT,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired):
            pass
        _, processes = psutil.wait_procs(processes, timeout=SHUTDOWN_TIMEOUT)

    for proc in processes:
        proc.terminate()
    _, alive = psutil.wait_procs(processes, timeout=SHUTDOWN_TIMEOUT)

    for proc in alive:
        proc.kill()
    psutil.wait_procs(alive, timeout=SHUTDOWN_TIMEOUT)

    time.sleep(2)
