import pytest

from steam_config_patcher.vdf.binary import (
    BinaryVdfError,
    Int64,
    Uint64,
    dumps,
    loads,
)

GOLDEN_DATA = {
    "shortcuts": {
        "0": {
            "appid": 123456,
            "AppName": "Game",
            "Exe": '"/games/game"',
            "IsHidden": 0,
            "tags": {},
        }
    }
}

GOLDEN_BYTES = (
    b"\x00shortcuts\x00\x000\x00\x02appid\x00@\xe2\x01\x00\x01AppName\x00Game\x00"
    b'\x01Exe\x00"/games/game"\x00\x02IsHidden\x00\x00\x00\x00\x00\x00tags\x00'
    b"\x08\x08\x08\x08"
)


def test_dumps_matches_valve_python_vdf_output():
    assert dumps(GOLDEN_DATA) == GOLDEN_BYTES


def test_loads_golden_bytes():
    assert loads(GOLDEN_BYTES) == GOLDEN_DATA


def test_round_trip():
    assert loads(dumps(GOLDEN_DATA)) == GOLDEN_DATA


def test_empty_input_loads_as_empty_dict():
    assert loads(b"") == {}


def test_empty_dict_dumps_to_no_bytes():
    assert dumps({}) == b""


def test_uint32_range_appid_round_trips():
    data = {"shortcuts": {"0": {"appid": 0x914B9DA1}}}

    assert loads(dumps(data)) == data


def test_uint32_boundaries_round_trip():
    data = {"d": {"min": 0, "max": 0xFFFFFFFF}}

    assert loads(dumps(data)) == data


def test_int_out_of_uint32_range_is_rejected():
    for value in (-1, 0x100000000):
        with pytest.raises(BinaryVdfError):
            dumps({"d": {"k": value}})


def test_uint64_and_int64_preserve_type():
    data = {"d": {"big": Uint64(2**40), "negative": Int64(-5)}}

    result = loads(dumps(data))

    assert isinstance(result["d"]["big"], Uint64)
    assert isinstance(result["d"]["negative"], Int64)
    assert result == data


def test_float_round_trips():
    data = {"d": {"f": 1.5}}

    assert loads(dumps(data)) == data


def test_utf8_strings_round_trip():
    data = {"d": {"name": "гейм ゲーム"}}

    assert loads(dumps(data)) == data


def test_alt_end_byte_closes_dict():
    assert loads(b"\x00d\x00\x0b\x08") == {"d": {}}


def test_trailing_data_is_rejected():
    with pytest.raises(BinaryVdfError):
        loads(GOLDEN_BYTES + b"\x00")


def test_truncated_data_is_rejected():
    with pytest.raises(BinaryVdfError):
        loads(GOLDEN_BYTES[:-3])


def test_unsupported_type_byte_is_rejected():
    with pytest.raises(BinaryVdfError):
        loads(b"\x05key\x00")


def test_unsupported_python_type_is_rejected():
    for value in (True, None, [1]):
        with pytest.raises(BinaryVdfError):
            dumps({"d": {"k": value}})


def test_null_byte_in_string_is_rejected():
    with pytest.raises(BinaryVdfError):
        dumps({"d": {"k": "a\x00b"}})
