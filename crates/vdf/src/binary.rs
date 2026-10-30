const TYPE_DICT: u8 = 0x00;
const TYPE_STRING: u8 = 0x01;
const TYPE_INT32: u8 = 0x02;
const TYPE_FLOAT32: u8 = 0x03;
const TYPE_UINT64: u8 = 0x07;
const TYPE_END: u8 = 0x08;
const TYPE_INT64: u8 = 0x0a;
const TYPE_END_ALT: u8 = 0x0b;

#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Dict(Dict),
    Str(String),
    Int32(u32),
    Float32(f32),
    Uint64(u64),
    Int64(i64),
}

pub type Dict = Vec<(String, Value)>;

pub type KeyReader<'a> = &'a dyn Fn(&[u8], usize) -> Result<(String, usize), String>;

pub trait DictExt {
    fn get(&self, key: &str) -> Option<&Value>;
    fn get_mut(&mut self, key: &str) -> Option<&mut Value>;
    fn insert_or_replace(&mut self, key: &str, value: Value);
    fn remove_key(&mut self, key: &str) -> bool;
}

impl DictExt for Dict {
    fn get(&self, key: &str) -> Option<&Value> {
        self.iter().find(|(k, _)| k == key).map(|(_, v)| v)
    }

    fn get_mut(&mut self, key: &str) -> Option<&mut Value> {
        self.iter_mut().find(|(k, _)| k == key).map(|(_, v)| v)
    }

    fn insert_or_replace(&mut self, key: &str, value: Value) {
        match self.iter_mut().find(|(k, _)| k == key) {
            Some((_, existing)) => *existing = value,
            None => self.push((key.to_string(), value)),
        }
    }

    fn remove_key(&mut self, key: &str) -> bool {
        let before = self.len();
        self.retain(|(k, _)| k != key);
        self.len() != before
    }
}

pub fn read_cstring(data: &[u8], offset: usize) -> Result<(String, usize), String> {
    let rest = data.get(offset..).ok_or("unexpected end of data")?;
    let end = rest
        .iter()
        .position(|&b| b == 0)
        .ok_or("unterminated string")?;
    let text = std::str::from_utf8(&rest[..end]).map_err(|e| e.to_string())?;
    Ok((text.to_string(), offset + end + 1))
}

fn read_array<const N: usize>(data: &[u8], offset: usize) -> Result<([u8; N], usize), String> {
    let bytes = data
        .get(offset..offset + N)
        .ok_or("unexpected end of data")?;
    let mut out = [0u8; N];
    out.copy_from_slice(bytes);
    Ok((out, offset + N))
}

fn read_dict(
    data: &[u8],
    mut offset: usize,
    top_level: bool,
    read_key: KeyReader,
) -> Result<(Dict, usize), String> {
    let mut result = Dict::new();
    loop {
        let Some(&value_type) = data.get(offset) else {
            if top_level {
                return Ok((result, offset));
            }
            return Err("unexpected end of data".into());
        };
        offset += 1;
        if value_type == TYPE_END || value_type == TYPE_END_ALT {
            return Ok((result, offset));
        }
        let (key, next) = read_key(data, offset)?;
        offset = next;
        let value = match value_type {
            TYPE_DICT => {
                let (dict, next) = read_dict(data, offset, false, read_key)?;
                offset = next;
                Value::Dict(dict)
            }
            TYPE_STRING => {
                let (s, next) = read_cstring(data, offset)?;
                offset = next;
                Value::Str(s)
            }
            TYPE_INT32 => {
                let (bytes, next) = read_array::<4>(data, offset)?;
                offset = next;
                Value::Int32(u32::from_le_bytes(bytes))
            }
            TYPE_FLOAT32 => {
                let (bytes, next) = read_array::<4>(data, offset)?;
                offset = next;
                Value::Float32(f32::from_le_bytes(bytes))
            }
            TYPE_UINT64 => {
                let (bytes, next) = read_array::<8>(data, offset)?;
                offset = next;
                Value::Uint64(u64::from_le_bytes(bytes))
            }
            TYPE_INT64 => {
                let (bytes, next) = read_array::<8>(data, offset)?;
                offset = next;
                Value::Int64(i64::from_le_bytes(bytes))
            }
            other => return Err(format!("unsupported value type 0x{other:02x}")),
        };
        result.push((key, value));
    }
}

pub fn loads(data: &[u8]) -> Result<Dict, String> {
    let (result, offset) = read_dict(data, 0, true, &read_cstring)?;
    if offset != data.len() {
        return Err("trailing data after top-level block".into());
    }
    Ok(result)
}

pub fn read_block(
    data: &[u8],
    offset: usize,
    read_key: KeyReader,
) -> Result<(Dict, usize), String> {
    read_dict(data, offset, false, read_key)
}

fn write_cstring(value: &str, out: &mut Vec<u8>) -> Result<(), String> {
    if value.as_bytes().contains(&0) {
        return Err("strings cannot contain null bytes".into());
    }
    out.extend_from_slice(value.as_bytes());
    out.push(0);
    Ok(())
}

fn write_dict(dict: &Dict, out: &mut Vec<u8>) -> Result<(), String> {
    for (key, value) in dict {
        match value {
            Value::Dict(inner) => {
                out.push(TYPE_DICT);
                write_cstring(key, out)?;
                write_dict(inner, out)?;
            }
            Value::Str(s) => {
                out.push(TYPE_STRING);
                write_cstring(key, out)?;
                write_cstring(s, out)?;
            }
            Value::Int32(n) => {
                out.push(TYPE_INT32);
                write_cstring(key, out)?;
                out.extend_from_slice(&n.to_le_bytes());
            }
            Value::Float32(f) => {
                out.push(TYPE_FLOAT32);
                write_cstring(key, out)?;
                out.extend_from_slice(&f.to_le_bytes());
            }
            Value::Uint64(n) => {
                out.push(TYPE_UINT64);
                write_cstring(key, out)?;
                out.extend_from_slice(&n.to_le_bytes());
            }
            Value::Int64(n) => {
                out.push(TYPE_INT64);
                write_cstring(key, out)?;
                out.extend_from_slice(&n.to_le_bytes());
            }
        }
    }
    out.push(TYPE_END);
    Ok(())
}

pub fn dumps(top: &Dict) -> Result<Vec<u8>, String> {
    if top.is_empty() {
        return Ok(Vec::new());
    }
    let mut out = Vec::new();
    write_dict(top, &mut out)?;
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::{Dict, DictExt, Value, dumps, loads};

    const GOLDEN_BYTES: &[u8] = b"\x00shortcuts\x00\x000\x00\x02appid\x00@\xe2\x01\x00\x01AppName\x00Game\x00\x01Exe\x00\"/games/game\"\x00\x02IsHidden\x00\x00\x00\x00\x00\x00tags\x00\x08\x08\x08\x08";

    fn dict(entries: Vec<(&str, Value)>) -> Dict {
        entries
            .into_iter()
            .map(|(k, v)| (k.to_string(), v))
            .collect()
    }

    fn golden() -> Dict {
        dict(vec![(
            "shortcuts",
            Value::Dict(dict(vec![(
                "0",
                Value::Dict(dict(vec![
                    ("appid", Value::Int32(123456)),
                    ("AppName", Value::Str("Game".into())),
                    ("Exe", Value::Str("\"/games/game\"".into())),
                    ("IsHidden", Value::Int32(0)),
                    ("tags", Value::Dict(Dict::new())),
                ])),
            )])),
        )])
    }

    #[test]
    fn dumps_matches_valve_python_vdf_output() {
        assert_eq!(dumps(&golden()).unwrap(), GOLDEN_BYTES);
    }

    #[test]
    fn loads_golden_bytes() {
        assert_eq!(loads(GOLDEN_BYTES).unwrap(), golden());
    }

    #[test]
    fn round_trip() {
        assert_eq!(loads(&dumps(&golden()).unwrap()).unwrap(), golden());
    }

    #[test]
    fn empty_input_loads_as_empty_dict() {
        assert_eq!(loads(b"").unwrap(), Dict::new());
    }

    #[test]
    fn empty_dict_dumps_to_no_bytes() {
        assert_eq!(dumps(&Dict::new()).unwrap(), b"");
    }

    #[test]
    fn generated_appid_range_round_trips() {
        let data = dict(vec![(
            "shortcuts",
            Value::Dict(dict(vec![(
                "0",
                Value::Dict(dict(vec![("appid", Value::Int32(0x914B9DA1))])),
            )])),
        )]);
        let bytes = dumps(&data).unwrap();
        assert!(
            bytes
                .windows(8)
                .any(|w| w == b"\x00\xa1\x9d\x4b\x91\x08\x08\x08")
        );
        assert_eq!(loads(&bytes).unwrap(), data);
    }

    #[test]
    fn uint32_boundaries_round_trip() {
        let data = dict(vec![(
            "d",
            Value::Dict(dict(vec![
                ("min", Value::Int32(0)),
                ("max", Value::Int32(0xFFFFFFFF)),
            ])),
        )]);
        assert_eq!(loads(&dumps(&data).unwrap()).unwrap(), data);
    }

    #[test]
    fn uint64_and_int64_preserve_type() {
        let data = dict(vec![(
            "d",
            Value::Dict(dict(vec![
                ("big", Value::Uint64(1 << 40)),
                ("negative", Value::Int64(-5)),
            ])),
        )]);
        assert_eq!(loads(&dumps(&data).unwrap()).unwrap(), data);
    }

    #[test]
    fn float_round_trips() {
        let data = dict(vec![(
            "d",
            Value::Dict(dict(vec![("f", Value::Float32(1.5))])),
        )]);
        assert_eq!(loads(&dumps(&data).unwrap()).unwrap(), data);
    }

    #[test]
    fn utf8_strings_round_trip() {
        let data = dict(vec![(
            "d",
            Value::Dict(dict(vec![("name", Value::Str("гейм ゲーム".into()))])),
        )]);
        assert_eq!(loads(&dumps(&data).unwrap()).unwrap(), data);
    }

    #[test]
    fn alt_end_byte_closes_dict() {
        assert_eq!(
            loads(b"\x00d\x00\x0b\x08").unwrap(),
            dict(vec![("d", Value::Dict(Dict::new()))])
        );
    }

    #[test]
    fn trailing_data_is_rejected() {
        let mut bytes = GOLDEN_BYTES.to_vec();
        bytes.push(0);
        assert!(loads(&bytes).is_err());
    }

    #[test]
    fn truncated_data_is_rejected() {
        assert!(loads(&GOLDEN_BYTES[..GOLDEN_BYTES.len() - 3]).is_err());
        assert!(loads(b"\x02appid\x00\x01\x02").is_err());
    }

    #[test]
    fn unsupported_type_byte_is_rejected() {
        assert!(loads(b"\x05key\x00").is_err());
    }

    #[test]
    fn null_byte_in_string_is_rejected() {
        let data = dict(vec![(
            "d",
            Value::Dict(dict(vec![("k", Value::Str("a\0b".into()))])),
        )]);
        assert!(dumps(&data).is_err());
    }

    #[test]
    fn dict_helpers_compare_keys_exactly() {
        let mut d = dict(vec![("AppName", Value::Str("a".into()))]);
        assert!(d.get("appname").is_none());
        assert_eq!(d.get("AppName"), Some(&Value::Str("a".into())));
        d.insert_or_replace("AppName", Value::Str("b".into()));
        d.insert_or_replace("Exe", Value::Str("".into()));
        assert_eq!(d.len(), 2);
        *d.get_mut("Exe").unwrap() = Value::Str("x".into());
        assert_eq!(d.get("Exe"), Some(&Value::Str("x".into())));
        assert!(d.remove_key("AppName"));
        assert!(!d.remove_key("AppName"));
        assert_eq!(d.len(), 1);
    }
}
