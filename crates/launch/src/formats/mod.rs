pub mod convars;
pub mod ini;
pub mod json;
pub mod keyvalue;
pub mod registry;
pub mod text;

use serde_json::Value;

const BOM: &[u8] = b"\xef\xbb\xbf";

pub fn utf8(existing: &[u8], what: &str) -> Result<(bool, String), String> {
    let bom = existing.starts_with(BOM);
    let body = if bom {
        &existing[BOM.len()..]
    } else {
        existing
    };
    String::from_utf8(body.to_vec())
        .map(|text| (bom, text))
        .map_err(|_| format!("the {what} is not utf-8"))
}

pub fn with_bom(bom: bool, mut out: Vec<u8>) -> Vec<u8> {
    if bom {
        out.splice(0..0, BOM.iter().copied());
    }
    out
}

pub fn apply(format: &str, content: &Value, existing: &[u8]) -> Result<Vec<u8>, String> {
    match format {
        "ini" => ini::apply(content, existing),
        "json" => json::apply(content, existing),
        "registry" => registry::apply(content, existing),
        "unityPrefs" => registry::apply_unity(content, existing),
        "keyvalue" => keyvalue::apply(content, existing),
        "sourceConvars" => convars::apply(content, existing),
        other => Err(format!("unknown format {other}")),
    }
}
