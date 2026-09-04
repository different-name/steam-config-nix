import struct

import pytest

from steam_config_patcher.vdf import binary
from steam_config_patcher.vdf.appinfo import (
    MAGIC_V40,
    MAGIC_V41,
    AppInfoError,
    icon_hash,
    load_common,
)

_APP_HEADER_AFTER_SIZE = 4 + 4 + 8 + 20 + 4 + 20


def _app_record(app_id, blob):
    size = _APP_HEADER_AFTER_SIZE + len(blob)
    header = struct.pack("<II", app_id, size)
    header += struct.pack("<II", 0, 0)
    header += struct.pack("<Q", 0)
    header += b"\x00" * 20
    header += struct.pack("<I", 0)
    header += b"\x00" * 20
    return header + blob


def _build_v40(apps):
    body = b""
    for app_id, common in apps.items():
        body += _app_record(app_id, binary.dumps({"appinfo": {"common": common}}))
    body += struct.pack("<I", 0)
    return struct.pack("<II", MAGIC_V40, 1) + body


def _encode_v41_blob(obj, strings):
    def index(value):
        if value not in strings:
            strings.append(value)
        return strings.index(value)

    parts = []

    def encode(node):
        for key, value in node.items():
            if isinstance(value, dict):
                parts.append(b"\x00" + struct.pack("<I", index(key)))
                encode(value)
            elif isinstance(value, str):
                parts.append(b"\x01" + struct.pack("<I", index(key)))
                parts.append(value.encode("utf-8") + b"\x00")
            else:
                parts.append(b"\x02" + struct.pack("<I", index(key)))
                parts.append(struct.pack("<I", value))
        parts.append(b"\x08")

    encode(obj)
    return b"".join(parts)


def _build_v41(apps):
    strings = []
    blobs = {
        app_id: _encode_v41_blob({"appinfo": {"common": common}}, strings)
        for app_id, common in apps.items()
    }

    header = struct.pack("<II", MAGIC_V41, 1)
    body = b"".join(_app_record(app_id, blob) for app_id, blob in blobs.items())
    body += struct.pack("<I", 0)

    string_table_offset = len(header) + 8 + len(body)
    string_table = struct.pack("<I", len(strings)) + b"".join(
        s.encode("utf-8") + b"\x00" for s in strings
    )

    return header + struct.pack("<q", string_table_offset) + body + string_table


APPS = {
    438100: {"name": "VRChat", "icon": "aaa111", "clienticon": "bbb222"},
    1091500: {"name": "Cyberpunk 2077", "icon": "ccc333", "clienticon": "ccc333"},
}


def test_v41_extracts_common_blocks():
    result = load_common(_build_v41(APPS))

    assert result[438100]["name"] == "VRChat"
    assert result[1091500]["name"] == "Cyberpunk 2077"


def test_v40_extracts_common_blocks():
    result = load_common(_build_v40(APPS))

    assert result[438100]["icon"] == "aaa111"
    assert result[1091500]["clienticon"] == "ccc333"


def test_app_ids_filter_limits_parsing():
    result = load_common(_build_v41(APPS), app_ids={1091500})

    assert set(result) == {1091500}


def test_icon_hash_prefers_icon_over_clienticon():
    result = load_common(_build_v41(APPS))

    assert icon_hash(result[438100]) == "aaa111"


def test_icon_hash_falls_back_to_clienticon():
    result = load_common(_build_v41({7: {"name": "X", "clienticon": "only"}}))

    assert icon_hash(result[7]) == "only"


def test_icon_hash_none_when_absent():
    assert icon_hash({"name": "X"}) is None


def test_unsupported_version_is_rejected():
    with pytest.raises(AppInfoError):
        load_common(struct.pack("<II", 0x07564427, 1))
