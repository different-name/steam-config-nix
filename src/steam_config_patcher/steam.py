from pathlib import Path
import psutil


def get_steam_user_ids(steam_dir: Path) -> list[int]:
    return [
        int(p.name)
        for p in (steam_dir / "userdata").iterdir()
        if p.is_dir() and p.name.isdigit() and p.name != "0"
    ]


def steam_is_closed(close_if_running=False) -> bool:
    closed = True
    for proc in psutil.process_iter(["name"]):
        if proc.name() == "steam":
            closed = False
            if close_if_running:
                proc.terminate()
                proc.wait(timeout=30)
                closed = True

    return closed
