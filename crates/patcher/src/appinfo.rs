use std::collections::{BTreeMap, BTreeSet};

use steam_config_vdf::binary::{Dict, DictExt, KeyReader, Value, read_block, read_cstring};

pub const MAGIC_V40: u32 = 0x07564428;
pub const MAGIC_V41: u32 = 0x07564429;

const APP_HEADER_AFTER_SIZE: usize = 4 + 4 + 8 + 20 + 4 + 20;

fn u32_at(data: &[u8], offset: usize) -> Result<u32, String> {
    let bytes = data
        .get(offset..offset + 4)
        .ok_or("unexpected end of appinfo.vdf")?;
    Ok(u32::from_le_bytes(bytes.try_into().unwrap()))
}

fn i64_at(data: &[u8], offset: usize) -> Result<i64, String> {
    let bytes = data
        .get(offset..offset + 8)
        .ok_or("unexpected end of appinfo.vdf")?;
    Ok(i64::from_le_bytes(bytes.try_into().unwrap()))
}

fn read_string_table(data: &[u8], offset: usize) -> Result<Vec<String>, String> {
    let count = u32_at(data, offset)?;
    let mut position = offset + 4;
    let mut strings = Vec::with_capacity(count as usize);
    for _ in 0..count {
        let (s, next) = read_cstring(data, position).map_err(|e| format!("string table: {e}"))?;
        strings.push(s);
        position = next;
    }
    Ok(strings)
}

pub fn load_common(data: &[u8], ids: &BTreeSet<u32>) -> Result<BTreeMap<u32, Dict>, String> {
    let magic = u32_at(data, 0)?;
    if magic != MAGIC_V40 && magic != MAGIC_V41 {
        return Err(format!("unsupported appinfo.vdf version 0x{magic:08x}"));
    }
    let mut offset = 8;
    let strings = if magic == MAGIC_V41 {
        let table_offset = i64_at(data, offset)?;
        offset += 8;
        Some(read_string_table(
            data,
            usize::try_from(table_offset).map_err(|_| "bad string table offset")?,
        )?)
    } else {
        None
    };
    let table_key: KeyReader = &|data, offset| {
        let index = u32_at(data, offset)? as usize;
        strings
            .as_ref()
            .and_then(|s| s.get(index))
            .map(|s| (s.clone(), offset + 4))
            .ok_or_else(|| format!("string table index {index} out of range"))
    };
    let read_key: KeyReader = if strings.is_some() {
        table_key
    } else {
        &read_cstring
    };

    let mut result = BTreeMap::new();
    while offset < data.len() {
        let app_id = u32_at(data, offset)?;
        if app_id == 0 {
            break;
        }
        let size = u32_at(data, offset + 4)? as usize;
        let next = offset + 8 + size;
        if ids.contains(&app_id) {
            let (block, _) = read_block(data, offset + 8 + APP_HEADER_AFTER_SIZE, read_key)?;
            if let Some(common) = find_common(&block) {
                result.insert(app_id, common.clone());
            }
        }
        offset = next;
    }
    Ok(result)
}

fn find_common(block: &Dict) -> Option<&Dict> {
    block.iter().find_map(|(_, v)| match v {
        Value::Dict(inner) => match inner.get("common") {
            Some(Value::Dict(common)) => Some(common),
            _ => None,
        },
        _ => None,
    })
}

pub fn icon_hash(common: &Dict) -> Option<&str> {
    ["icon", "clienticon"]
        .iter()
        .find_map(|key| match common.get(key) {
            Some(Value::Str(s)) if !s.is_empty() => Some(s.as_str()),
            _ => None,
        })
}

#[cfg(test)]
pub mod fixtures {
    use super::{APP_HEADER_AFTER_SIZE, MAGIC_V40, MAGIC_V41};
    use steam_config_vdf::binary::{Dict, Value, dumps};

    pub fn common(name: &str, icon: Option<&str>, clienticon: Option<&str>) -> Dict {
        let mut d: Dict = vec![("name".into(), Value::Str(name.into()))];
        if let Some(icon) = icon {
            d.push(("icon".into(), Value::Str(icon.into())));
        }
        if let Some(clienticon) = clienticon {
            d.push(("clienticon".into(), Value::Str(clienticon.into())));
        }
        d
    }

    fn app_record(app_id: u32, blob: &[u8]) -> Vec<u8> {
        let size = APP_HEADER_AFTER_SIZE + blob.len();
        let mut out = Vec::new();
        out.extend_from_slice(&app_id.to_le_bytes());
        out.extend_from_slice(&(size as u32).to_le_bytes());
        out.extend_from_slice(&[0u8; APP_HEADER_AFTER_SIZE]);
        out.extend_from_slice(blob);
        out
    }

    fn wrap(common: &Dict) -> Dict {
        vec![(
            "appinfo".into(),
            Value::Dict(vec![("common".into(), Value::Dict(common.clone()))]),
        )]
    }

    pub fn build_v40(apps: &[(u32, Dict)]) -> Vec<u8> {
        let mut out = Vec::new();
        out.extend_from_slice(&MAGIC_V40.to_le_bytes());
        out.extend_from_slice(&1u32.to_le_bytes());
        for (app_id, common) in apps {
            out.extend_from_slice(&app_record(*app_id, &dumps(&wrap(common)).unwrap()));
        }
        out.extend_from_slice(&0u32.to_le_bytes());
        out
    }

    fn index(strings: &mut Vec<String>, key: &str) -> u32 {
        match strings.iter().position(|s| s == key) {
            Some(i) => i as u32,
            None => {
                strings.push(key.to_string());
                (strings.len() - 1) as u32
            }
        }
    }

    fn encode_v41(dict: &Dict, strings: &mut Vec<String>, out: &mut Vec<u8>) {
        for (key, value) in dict {
            match value {
                Value::Dict(inner) => {
                    out.push(0x00);
                    out.extend_from_slice(&index(strings, key).to_le_bytes());
                    encode_v41(inner, strings, out);
                }
                Value::Str(s) => {
                    out.push(0x01);
                    out.extend_from_slice(&index(strings, key).to_le_bytes());
                    out.extend_from_slice(s.as_bytes());
                    out.push(0);
                }
                Value::Int32(n) => {
                    out.push(0x02);
                    out.extend_from_slice(&index(strings, key).to_le_bytes());
                    out.extend_from_slice(&n.to_le_bytes());
                }
                _ => unreachable!(),
            }
        }
        out.push(0x08);
    }

    pub fn build_v41(apps: &[(u32, Dict)]) -> Vec<u8> {
        let mut strings = Vec::new();
        let mut body = Vec::new();
        for (app_id, common) in apps {
            let mut blob = Vec::new();
            encode_v41(&wrap(common), &mut strings, &mut blob);
            body.extend_from_slice(&app_record(*app_id, &blob));
        }
        body.extend_from_slice(&0u32.to_le_bytes());
        let table_offset = 8 + 8 + body.len();
        let mut out = Vec::new();
        out.extend_from_slice(&MAGIC_V41.to_le_bytes());
        out.extend_from_slice(&1u32.to_le_bytes());
        out.extend_from_slice(&(table_offset as i64).to_le_bytes());
        out.extend_from_slice(&body);
        out.extend_from_slice(&(strings.len() as u32).to_le_bytes());
        for s in &strings {
            out.extend_from_slice(s.as_bytes());
            out.push(0);
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::fixtures::{build_v40, build_v41, common};
    use super::{icon_hash, load_common};
    use std::collections::BTreeSet;
    use steam_config_vdf::binary::{Dict, DictExt, Value};

    fn apps() -> Vec<(u32, Dict)> {
        vec![
            (438100, common("VRChat", Some("aaa111"), Some("bbb222"))),
            (
                1091500,
                common("Cyberpunk 2077", Some("ccc333"), Some("ccc333")),
            ),
        ]
    }

    fn all() -> BTreeSet<u32> {
        [438100, 1091500, 7].into_iter().collect()
    }

    fn name(d: &Dict, key: &str) -> String {
        match d.get(key) {
            Some(Value::Str(s)) => s.clone(),
            other => panic!("{key}: {other:?}"),
        }
    }

    #[test]
    fn v41_extracts_common_blocks() {
        let result = load_common(&build_v41(&apps()), &all()).unwrap();
        assert_eq!(name(&result[&438100], "name"), "VRChat");
        assert_eq!(name(&result[&1091500], "name"), "Cyberpunk 2077");
    }

    #[test]
    fn v40_extracts_common_blocks() {
        let result = load_common(&build_v40(&apps()), &all()).unwrap();
        assert_eq!(name(&result[&438100], "icon"), "aaa111");
        assert_eq!(name(&result[&1091500], "clienticon"), "ccc333");
    }

    #[test]
    fn app_ids_filter_limits_parsing() {
        let ids = [1091500].into_iter().collect();
        let result = load_common(&build_v41(&apps()), &ids).unwrap();
        let keys: Vec<u32> = result.keys().copied().collect();
        assert_eq!(keys, vec![1091500]);
    }

    #[test]
    fn icon_hash_prefers_icon_over_clienticon() {
        let result = load_common(&build_v41(&apps()), &all()).unwrap();
        assert_eq!(icon_hash(&result[&438100]), Some("aaa111"));
    }

    #[test]
    fn icon_hash_falls_back_to_clienticon() {
        let result =
            load_common(&build_v41(&[(7, common("X", None, Some("only")))]), &all()).unwrap();
        assert_eq!(icon_hash(&result[&7]), Some("only"));
    }

    #[test]
    fn icon_hash_none_when_absent() {
        assert_eq!(icon_hash(&common("X", None, None)), None);
        assert_eq!(icon_hash(&common("X", Some(""), None)), None);
    }

    #[test]
    fn unsupported_version_is_rejected() {
        let mut data = Vec::new();
        data.extend_from_slice(&0x07564427u32.to_le_bytes());
        data.extend_from_slice(&1u32.to_le_bytes());
        assert!(load_common(&data, &all()).is_err());
        assert!(load_common(b"\x28", &all()).is_err());
    }
}
