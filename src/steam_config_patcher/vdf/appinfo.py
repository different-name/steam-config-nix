import struct
from typing import Optional

from steam_config_patcher.vdf import binary

MAGIC_V40 = 0x07564428
MAGIC_V41 = 0x07564429

_HEADER = struct.Struct("<II")
_STRING_TABLE_OFFSET = struct.Struct("<q")
_UINT32 = struct.Struct("<I")

_APP_HEADER_AFTER_SIZE = 4 + 4 + 8 + 20 + 4 + 20


class AppInfoError(ValueError):
    pass


def _read_string_table(data: bytes, offset: int) -> list[str]:
    (count,) = _UINT32.unpack_from(data, offset)
    position = offset + _UINT32.size
    strings = []
    for _ in range(count):
        end = data.find(b"\x00", position)
        if end == -1:
            raise AppInfoError("unterminated string in string table")
        strings.append(data[position:end].decode("utf-8"))
        position = end + 1
    return strings


def _string_table_key_reader(strings: list[str]) -> binary.KeyReader:
    def read_key(data: bytes, offset: int) -> tuple[str, int]:
        (index,) = _UINT32.unpack_from(data, offset)
        try:
            return strings[index], offset + _UINT32.size
        except IndexError:
            raise AppInfoError(f"string table index {index} out of range")

    return read_key


def load_common(data: bytes, app_ids: Optional[set[int]] = None) -> dict[int, dict]:
    (magic, _universe) = _HEADER.unpack_from(data, 0)
    if magic not in (MAGIC_V40, MAGIC_V41):
        raise AppInfoError(f"unsupported appinfo.vdf version 0x{magic:08x}")

    offset = _HEADER.size
    read_key = binary._read_cstring
    if magic == MAGIC_V41:
        (string_table_offset,) = _STRING_TABLE_OFFSET.unpack_from(data, offset)
        offset += _STRING_TABLE_OFFSET.size
        read_key = _string_table_key_reader(
            _read_string_table(data, string_table_offset)
        )

    result: dict[int, dict] = {}
    while offset < len(data):
        (app_id,) = _UINT32.unpack_from(data, offset)
        if app_id == 0:
            break
        (size,) = _UINT32.unpack_from(data, offset + _UINT32.size)
        next_offset = offset + 2 * _UINT32.size + size

        if app_ids is None or app_id in app_ids:
            blob_offset = offset + 2 * _UINT32.size + _APP_HEADER_AFTER_SIZE
            block, _ = binary.read_block(data, blob_offset, read_key=read_key)
            common = _find_common(block)
            if common is not None:
                result[app_id] = common

        offset = next_offset

    return result


def _find_common(block: dict) -> Optional[dict]:
    for value in block.values():
        if isinstance(value, dict):
            common = value.get("common")
            if isinstance(common, dict):
                return common
    return None


def icon_hash(common: dict) -> Optional[str]:
    for key in ("icon", "clienticon"):
        value = common.get(key)
        if isinstance(value, str) and value:
            return value
    return None
