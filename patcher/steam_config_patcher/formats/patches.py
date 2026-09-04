import json
import struct

from steam_config_patcher.formats import ini, reg, sourceconvars
from steam_config_patcher.types import PatchOp
from steam_config_patcher.vdf import text as vdf_text
from steam_config_patcher.vdf.text import VdfNode


def _deep_merge(base: dict, overlay: dict) -> dict:
    result = dict(base)
    for key, value in overlay.items():
        existing = result.get(key)
        if isinstance(existing, dict) and isinstance(value, dict):
            result[key] = _deep_merge(existing, value)
        else:
            result[key] = value
    return result


def _render_json_patch(content: dict, existing: bytes) -> bytes:
    base = json.loads(existing) if existing.strip() else {}
    merged = _deep_merge(base, content)
    return (json.dumps(merged, indent=2) + "\n").encode("utf-8")


def _kv_apply(root: VdfNode, content: dict, prefix: tuple[str, ...]) -> None:
    for key, value in content.items():
        path = (*prefix, str(key))
        if isinstance(value, dict):
            _kv_apply(root, value, path)
        else:
            root.set_path(path, str(value))


def _render_keyvalue_patch(content: dict, existing: bytes) -> bytes:
    text = existing.decode("utf-8")
    root = vdf_text.loads(text) if text.strip() else VdfNode(children=[])
    _kv_apply(root, content, ())
    return vdf_text.dumps(root).encode("utf-8")


def _reg_render_value(name: str, value: object) -> str:
    quoted_name = f'"{reg.escape(name)}"'
    if isinstance(value, bool):
        return f"{quoted_name}=dword:{(1 if value else 0):08x}"
    if isinstance(value, int):
        return f"{quoted_name}=dword:{value & 0xFFFFFFFF:08x}"
    return f'{quoted_name}="{reg.escape(str(value))}"'


def _reg_set_value(section: reg.Section, name: str, value: object) -> None:
    reg.put_line(section, name, _reg_render_value(name, value))


def _render_registry_patch(content: dict, existing: bytes) -> bytes:
    return reg.apply(content, existing, _reg_set_value)


def unity_prefs_hash(key: str) -> int:
    h = 5381
    for b in key.encode("utf-8"):
        h = ((h * 33) ^ b) & 0xFFFFFFFF
    return h


def _unity_render_value(value: object) -> str:
    if isinstance(value, bool):
        return f"dword:{(1 if value else 0):08x}"
    if isinstance(value, int):
        return f"dword:{value & 0xFFFFFFFF:08x}"
    if isinstance(value, float):
        return "hex(4):" + ",".join(f"{b:02x}" for b in struct.pack("<d", value))
    data = str(value).encode("utf-8") + b"\x00"
    return "hex:" + ",".join(f"{b:02x}" for b in data)


def _render_unity_prefs_patch(content: dict, existing: bytes) -> bytes:
    def set_value(section: reg.Section, pref_key: str, value: object) -> None:
        name = f"{pref_key}_h{unity_prefs_hash(pref_key)}"
        reg.put_line(section, name, f'"{reg.escape(name)}"={_unity_render_value(value)}')

    return reg.apply(content, existing, set_value)


def render(patch_op: PatchOp, existing: bytes) -> bytes:
    if patch_op.format == "json":
        return _render_json_patch(patch_op.content, existing)
    if patch_op.format == "ini":
        return ini.apply(patch_op.content, existing)
    if patch_op.format == "registry":
        return _render_registry_patch(patch_op.content, existing)
    if patch_op.format == "unityPrefs":
        return _render_unity_prefs_patch(patch_op.content, existing)
    if patch_op.format == "sourceConvars":
        return sourceconvars.render(patch_op.content, existing)
    return _render_keyvalue_patch(patch_op.content, existing)
