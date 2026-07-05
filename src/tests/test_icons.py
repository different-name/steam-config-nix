import struct

from PIL import Image

from steam_config_patcher import icons
from steam_config_patcher.vdf import binary
from steam_config_patcher.vdf.appinfo import MAGIC_V40

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


def _build_appinfo(apps):
    body = b""
    for app_id, common in apps.items():
        body += _app_record(app_id, binary.dumps({"appinfo": {"common": common}}))
    body += struct.pack("<I", 0)
    return struct.pack("<II", MAGIC_V40, 1) + body


def _make_steam_dir(tmp_path, apps, icon_files):
    steam = tmp_path / "steam"
    appcache = steam / "appcache"
    appcache.mkdir(parents=True)
    (appcache / "appinfo.vdf").write_bytes(_build_appinfo(apps))
    for app_id, (hash_, image) in icon_files.items():
        directory = appcache / "librarycache" / str(app_id)
        directory.mkdir(parents=True)
        image.save(directory / f"{hash_}.jpg")
    return steam


def _managed(home, size, app_id):
    return (
        home
        / ".local/share/icons/hicolor"
        / size
        / "apps"
        / f"steam-config-nix-{app_id}.png"
    )


def _set_home(monkeypatch, tmp_path, data_dirs=None):
    monkeypatch.setenv("HOME", str(tmp_path / "home"))
    monkeypatch.setenv("XDG_DATA_DIRS", data_dirs or str(tmp_path / "no-such-dir"))
    return tmp_path / "home"


def _make_fallback(tmp_path):
    data_dir = tmp_path / "share"
    fallback = data_dir / "icons/hicolor/48x48/apps/steam.png"
    fallback.parent.mkdir(parents=True)
    Image.new("RGB", (48, 48), "blue").save(fallback)
    return data_dir


def test_apply_writes_resolved_icon_as_png(tmp_path, monkeypatch):
    home = _set_home(monkeypatch, tmp_path)
    steam = _make_steam_dir(
        tmp_path,
        {620: {"name": "Portal", "icon": "abc123"}},
        {620: ("abc123", Image.new("RGB", (32, 32), "red"))},
    )

    icons.apply_library_icons(steam, {620})

    out = _managed(home, "32x32", 620)
    assert out.is_file()
    with Image.open(out) as image:
        assert image.format == "PNG"
        assert image.size == (32, 32)


def test_apply_removes_unconfigured_icons(tmp_path, monkeypatch):
    home = _set_home(monkeypatch, tmp_path)
    steam = _make_steam_dir(
        tmp_path,
        {620: {"name": "Portal", "icon": "abc123"}},
        {620: ("abc123", Image.new("RGB", (32, 32), "red"))},
    )

    icons.apply_library_icons(steam, {620})
    assert _managed(home, "32x32", 620).is_file()

    icons.apply_library_icons(steam, set())
    assert not _managed(home, "32x32", 620).exists()


def test_apply_uses_fallback_when_icon_missing(tmp_path, monkeypatch):
    data_dir = _make_fallback(tmp_path)
    home = _set_home(monkeypatch, tmp_path, data_dirs=str(data_dir))
    steam = _make_steam_dir(tmp_path, {620: {"name": "Portal", "icon": "gone"}}, {})

    icons.apply_library_icons(steam, {620})

    assert _managed(home, "48x48", 620).is_file()


def test_apply_falls_back_on_unparseable_appinfo(tmp_path, monkeypatch):
    data_dir = _make_fallback(tmp_path)
    home = _set_home(monkeypatch, tmp_path, data_dirs=str(data_dir))
    steam = tmp_path / "steam"
    (steam / "appcache").mkdir(parents=True)
    (steam / "appcache" / "appinfo.vdf").write_bytes(struct.pack("<II", 0x07564427, 1))

    icons.apply_library_icons(steam, {620})

    assert _managed(home, "48x48", 620).is_file()


def test_apply_no_apps_is_noop(tmp_path, monkeypatch):
    home = _set_home(monkeypatch, tmp_path)
    steam = _make_steam_dir(tmp_path, {}, {})

    icons.apply_library_icons(steam, set())

    assert not (home / ".local/share/icons/hicolor").exists()
