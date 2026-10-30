use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::io::Cursor;
use std::path::{Path, PathBuf};

use steam_config_vdf::binary::Dict;

use crate::appinfo;
use crate::fileio::write_atomic;
use crate::log;

const PREFIX: &str = "steam-config-nix-";

fn remove_managed(hicolor: &Path) {
    let Ok(sizes) = fs::read_dir(hicolor) else {
        return;
    };
    for size in sizes.flatten() {
        let Ok(apps) = fs::read_dir(size.path().join("apps")) else {
            continue;
        };
        for entry in apps.flatten() {
            if entry.file_name().to_string_lossy().starts_with(PREFIX) {
                if let Err(e) = fs::remove_file(entry.path()) {
                    log(format!("{}: {e}", entry.path().display()));
                }
            }
        }
    }
}

fn librarycache_icon(steam_dir: &Path, app_id: u32, hash: &str) -> Option<PathBuf> {
    let dir = steam_dir
        .join("appcache/librarycache")
        .join(app_id.to_string());
    ["jpg", "png", "ico"]
        .iter()
        .map(|ext| dir.join(format!("{hash}.{ext}")))
        .find(|p| p.is_file())
}

fn fallback(bases: &[PathBuf]) -> Option<PathBuf> {
    let mut best: Option<(u32, PathBuf)> = None;
    for base in bases {
        let Ok(sizes) = fs::read_dir(base.join("hicolor")) else {
            continue;
        };
        for size in sizes.flatten() {
            let candidate = size.path().join("apps/steam.png");
            if !candidate.is_file() {
                continue;
            }
            let n: u32 = size
                .file_name()
                .to_string_lossy()
                .split('x')
                .next()
                .and_then(|s| s.parse().ok())
                .unwrap_or(0);
            if best.as_ref().is_none_or(|(b, _)| n > *b) {
                best = Some((n, candidate));
            }
        }
    }
    best.map(|(_, p)| p)
}

fn render_png(source: &Path) -> Result<(Vec<u8>, u32, u32), String> {
    let image = image::open(source).map_err(|e| e.to_string())?.to_rgba8();
    let (w, h) = image.dimensions();
    let mut buf = Vec::new();
    image::DynamicImage::ImageRgba8(image)
        .write_to(&mut Cursor::new(&mut buf), image::ImageFormat::Png)
        .map_err(|e| e.to_string())?;
    Ok((buf, w, h))
}

pub fn apply(steam_dir: &Path, ids: &BTreeSet<u32>, icons_dir: &Path, data_dirs: &[PathBuf]) {
    let hicolor = icons_dir.join("hicolor");
    remove_managed(&hicolor);
    if ids.is_empty() {
        return;
    }
    let common: BTreeMap<u32, Dict> = match fs::read(steam_dir.join("appcache/appinfo.vdf")) {
        Ok(data) => match appinfo::load_common(&data, ids) {
            Ok(common) => common,
            Err(e) => {
                log(format!(
                    "appinfo.vdf could not be read ({e}), using the Steam icon"
                ));
                BTreeMap::new()
            }
        },
        Err(e) => {
            log(format!(
                "appinfo.vdf could not be read ({e}), using the Steam icon"
            ));
            BTreeMap::new()
        }
    };
    let mut bases = vec![icons_dir.to_path_buf()];
    bases.extend(data_dirs.iter().map(|d| d.join("icons")));
    let fallback = fallback(&bases);
    for id in ids {
        let source = common
            .get(id)
            .and_then(|c| appinfo::icon_hash(c))
            .and_then(|hash| librarycache_icon(steam_dir, *id, hash))
            .or_else(|| fallback.clone());
        let Some(source) = source else {
            log(format!("no icon available for {id}"));
            continue;
        };
        let (png, w, h) = match render_png(&source) {
            Ok(r) => r,
            Err(e) => {
                log(format!("icon for {id} could not be read: {e}"));
                continue;
            }
        };
        let dir = hicolor.join(format!("{w}x{h}/apps"));
        let path = dir.join(format!("{PREFIX}{id}.png"));
        if let Err(e) = fs::create_dir_all(&dir).and_then(|_| write_atomic(&path, &png)) {
            log(format!("{}: {e}", path.display()));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::apply;
    use crate::appinfo::fixtures::{build_v40, common};
    use crate::writers::testing::temp;
    use std::collections::BTreeSet;
    use std::fs;
    use std::path::PathBuf;

    fn steam_dir(root: &PathBuf, with_icon: bool) -> PathBuf {
        let steam = root.join("steam");
        fs::create_dir_all(steam.join("appcache")).unwrap();
        let hash = if with_icon { "abc123" } else { "gone" };
        fs::write(
            steam.join("appcache/appinfo.vdf"),
            build_v40(&[(620, common("Portal", Some(hash), None))]),
        )
        .unwrap();
        if with_icon {
            let dir = steam.join("appcache/librarycache/620");
            fs::create_dir_all(&dir).unwrap();
            image::RgbImage::from_pixel(32, 32, image::Rgb([255, 0, 0]))
                .save(dir.join("abc123.jpg"))
                .unwrap();
        }
        steam
    }

    fn fallback_dir(root: &PathBuf) -> PathBuf {
        let data = root.join("share");
        let dir = data.join("icons/hicolor/48x48/apps");
        fs::create_dir_all(&dir).unwrap();
        image::RgbImage::from_pixel(48, 48, image::Rgb([0, 0, 255]))
            .save(dir.join("steam.png"))
            .unwrap();
        data
    }

    fn managed(icons: &PathBuf, size: &str) -> PathBuf {
        icons.join(format!("hicolor/{size}/apps/steam-config-nix-620.png"))
    }

    #[test]
    fn writes_the_resolved_icon_as_png_and_removes_it_when_unconfigured() {
        let root = temp("icons-write");
        let steam = steam_dir(&root, true);
        let icons = root.join("icons");
        apply(&steam, &[620].into_iter().collect(), &icons, &[]);
        let out = managed(&icons, "32x32");
        let img = image::open(&out).unwrap();
        assert_eq!(img.width(), 32);
        assert_eq!(
            image::guess_format(&fs::read(&out).unwrap()).unwrap(),
            image::ImageFormat::Png
        );
        apply(&steam, &BTreeSet::new(), &icons, &[]);
        assert!(!out.exists());
    }

    #[test]
    fn uses_the_fallback_when_the_icon_or_appinfo_is_missing() {
        let root = temp("icons-fallback");
        let steam = steam_dir(&root, false);
        let icons = root.join("icons");
        let data = fallback_dir(&root);
        apply(
            &steam,
            &[620].into_iter().collect(),
            &icons,
            &[data.clone()],
        );
        assert!(managed(&icons, "48x48").is_file());
        fs::write(
            steam.join("appcache/appinfo.vdf"),
            0x07564427u32.to_le_bytes(),
        )
        .unwrap();
        apply(
            &steam,
            &[620].into_iter().collect(),
            &icons,
            &[data.clone()],
        );
        assert!(managed(&icons, "48x48").is_file());
        fs::remove_file(steam.join("appcache/appinfo.vdf")).unwrap();
        apply(&steam, &[620].into_iter().collect(), &icons, &[data]);
        assert!(managed(&icons, "48x48").is_file());
    }

    #[test]
    fn no_apps_is_a_noop() {
        let root = temp("icons-noop");
        let steam = steam_dir(&root, false);
        let icons = root.join("icons");
        apply(&steam, &BTreeSet::new(), &icons, &[]);
        assert!(!icons.exists());
    }
}
