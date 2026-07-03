import struct
from typing import Union

_TYPE_DICT = 0x00
_TYPE_STRING = 0x01
_TYPE_INT32 = 0x02
_TYPE_FLOAT32 = 0x03
_TYPE_UINT64 = 0x07
_TYPE_END = 0x08
_TYPE_INT64 = 0x0A
_TYPE_END_ALT = 0x0B

_UINT32 = struct.Struct("<I")
_UINT64 = struct.Struct("<Q")
_INT64 = struct.Struct("<q")
_FLOAT32 = struct.Struct("<f")

BinaryVdfValue = Union[dict, str, int, float]


class Uint64(int):
    pass


class Int64(int):
    pass


class BinaryVdfError(ValueError):
    pass


def _read_cstring(data: bytes, offset: int) -> tuple[str, int]:
    end = data.find(b"\x00", offset)
    if end == -1:
        raise BinaryVdfError("unterminated string")
    return data[offset:end].decode("utf-8"), end + 1


def _read_dict(data: bytes, offset: int, top_level: bool) -> tuple[dict, int]:
    result: dict[str, BinaryVdfValue] = {}
    while True:
        if offset >= len(data):
            if top_level:
                return result, offset
            raise BinaryVdfError("unexpected end of data")

        value_type = data[offset]
        offset += 1
        if value_type in (_TYPE_END, _TYPE_END_ALT):
            return result, offset

        key, offset = _read_cstring(data, offset)

        if value_type == _TYPE_DICT:
            value, offset = _read_dict(data, offset, top_level=False)
        elif value_type == _TYPE_STRING:
            value, offset = _read_cstring(data, offset)
        elif value_type == _TYPE_INT32:
            (value,) = _UINT32.unpack_from(data, offset)
            offset += _UINT32.size
        elif value_type == _TYPE_UINT64:
            (raw,) = _UINT64.unpack_from(data, offset)
            value = Uint64(raw)
            offset += _UINT64.size
        elif value_type == _TYPE_INT64:
            (raw,) = _INT64.unpack_from(data, offset)
            value = Int64(raw)
            offset += _INT64.size
        elif value_type == _TYPE_FLOAT32:
            (value,) = _FLOAT32.unpack_from(data, offset)
            offset += _FLOAT32.size
        else:
            raise BinaryVdfError(f"unsupported value type 0x{value_type:02x}")

        result[key] = value

    return result, offset


def loads(data: bytes) -> dict:
    result, offset = _read_dict(data, 0, top_level=True)
    if offset != len(data):
        raise BinaryVdfError("trailing data after top-level block")
    return result


def _write_cstring(value: str, parts: list[bytes]) -> None:
    encoded = value.encode("utf-8")
    if b"\x00" in encoded:
        raise BinaryVdfError("strings cannot contain null bytes")
    parts.append(encoded)
    parts.append(b"\x00")


def _write_dict(obj: dict, parts: list[bytes]) -> None:
    for key, value in obj.items():
        if isinstance(value, dict):
            parts.append(bytes([_TYPE_DICT]))
            _write_cstring(key, parts)
            _write_dict(value, parts)
        elif isinstance(value, str):
            parts.append(bytes([_TYPE_STRING]))
            _write_cstring(key, parts)
            _write_cstring(value, parts)
        elif isinstance(value, Uint64):
            parts.append(bytes([_TYPE_UINT64]))
            _write_cstring(key, parts)
            parts.append(_UINT64.pack(value))
        elif isinstance(value, Int64):
            parts.append(bytes([_TYPE_INT64]))
            _write_cstring(key, parts)
            parts.append(_INT64.pack(value))
        elif isinstance(value, bool):
            raise BinaryVdfError(f"unsupported value type for key {key!r}: bool")
        elif isinstance(value, int):
            if not 0 <= value <= 0xFFFFFFFF:
                raise BinaryVdfError(f"int value out of uint32 range for key {key!r}")
            parts.append(bytes([_TYPE_INT32]))
            _write_cstring(key, parts)
            parts.append(_UINT32.pack(value))
        elif isinstance(value, float):
            parts.append(bytes([_TYPE_FLOAT32]))
            _write_cstring(key, parts)
            parts.append(_FLOAT32.pack(value))
        else:
            raise BinaryVdfError(
                f"unsupported value type for key {key!r}: {type(value).__name__}"
            )
    parts.append(bytes([_TYPE_END]))


def dumps(obj: dict) -> bytes:
    if not obj:
        return b""
    parts: list[bytes] = []
    _write_dict(obj, parts)
    return b"".join(parts)
