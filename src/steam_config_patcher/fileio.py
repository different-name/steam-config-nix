import os
from pathlib import Path


def atomic_write_bytes(path: Path, data: bytes) -> None:
    tmp_path = path.with_name(path.name + ".tmp")
    with tmp_path.open("wb") as f:
        f.write(data)
        f.flush()
        os.fsync(f.fileno())
    tmp_path.replace(path)


def atomic_write_text(path: Path, text: str) -> None:
    atomic_write_bytes(path, text.encode("utf-8"))
