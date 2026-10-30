#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Encoding {
    Utf8,
    Utf16Le,
    Utf16Be,
    Utf32Le,
    Utf32Be,
}

pub struct Text {
    pub body: String,
    pub encoding: Encoding,
    pub bom: bool,
}

const BOMS: [(&[u8], Encoding); 5] = [
    (&[0x00, 0x00, 0xfe, 0xff], Encoding::Utf32Be),
    (&[0xff, 0xfe, 0x00, 0x00], Encoding::Utf32Le),
    (&[0xef, 0xbb, 0xbf], Encoding::Utf8),
    (&[0xff, 0xfe], Encoding::Utf16Le),
    (&[0xfe, 0xff], Encoding::Utf16Be),
];

fn utf16(bytes: &[u8], le: bool) -> Result<String, String> {
    if bytes.len() % 2 != 0 {
        return Err("odd byte count for utf-16".into());
    }
    let units: Vec<u16> = bytes
        .chunks(2)
        .map(|c| {
            if le {
                u16::from_le_bytes([c[0], c[1]])
            } else {
                u16::from_be_bytes([c[0], c[1]])
            }
        })
        .collect();
    String::from_utf16(&units).map_err(|_| "invalid utf-16".into())
}

fn utf32(bytes: &[u8], le: bool) -> Result<String, String> {
    if bytes.len() % 4 != 0 {
        return Err("the byte count is not a multiple of 4 for utf-32".into());
    }
    bytes
        .chunks(4)
        .map(|c| {
            let b = [c[0], c[1], c[2], c[3]];
            char::from_u32(if le {
                u32::from_le_bytes(b)
            } else {
                u32::from_be_bytes(b)
            })
            .ok_or("invalid utf-32")
        })
        .collect::<Result<String, _>>()
        .map_err(String::from)
}

// windows writes utf-16 without a mark, and reading those bytes as utf-8 corrupts the file
fn sniff(bytes: &[u8]) -> Result<Encoding, String> {
    let even = bytes.iter().step_by(2).any(|b| *b == 0);
    let odd = bytes.iter().skip(1).step_by(2).any(|b| *b == 0);
    match (even, odd) {
        (false, true) => Ok(Encoding::Utf16Le),
        (true, false) => Ok(Encoding::Utf16Be),
        _ => Err("the file is not text we can edit".into()),
    }
}

pub fn decode(bytes: &[u8]) -> Result<Text, String> {
    for (bom, encoding) in BOMS {
        if bytes.starts_with(bom) {
            let body = decode_as(&bytes[bom.len()..], encoding)?;
            return Ok(Text {
                body,
                encoding,
                bom: true,
            });
        }
    }
    let encoding = if bytes.contains(&0) {
        sniff(bytes)?
    } else {
        Encoding::Utf8
    };
    Ok(Text {
        body: decode_as(bytes, encoding)?,
        encoding,
        bom: false,
    })
}

fn decode_as(bytes: &[u8], encoding: Encoding) -> Result<String, String> {
    match encoding {
        Encoding::Utf8 => {
            String::from_utf8(bytes.to_vec()).map_err(|_| "the file is not valid utf-8".into())
        }
        Encoding::Utf16Le => utf16(bytes, true),
        Encoding::Utf16Be => utf16(bytes, false),
        Encoding::Utf32Le => utf32(bytes, true),
        Encoding::Utf32Be => utf32(bytes, false),
    }
}

pub fn encode(text: &Text, body: &str) -> Vec<u8> {
    let mut out = Vec::new();
    if text.bom {
        out.extend_from_slice(
            BOMS.iter()
                .find(|(_, e)| *e == text.encoding)
                .map(|(b, _)| *b)
                .unwrap_or(&[]),
        );
    }
    match text.encoding {
        Encoding::Utf8 => out.extend_from_slice(body.as_bytes()),
        Encoding::Utf16Le => body
            .encode_utf16()
            .for_each(|u| out.extend_from_slice(&u.to_le_bytes())),
        Encoding::Utf16Be => body
            .encode_utf16()
            .for_each(|u| out.extend_from_slice(&u.to_be_bytes())),
        Encoding::Utf32Le => body
            .chars()
            .for_each(|c| out.extend_from_slice(&(c as u32).to_le_bytes())),
        Encoding::Utf32Be => body
            .chars()
            .for_each(|c| out.extend_from_slice(&(c as u32).to_be_bytes())),
    }
    out
}

pub struct Line {
    pub body: String,
    pub ending: String,
}

pub fn split(text: &str) -> Vec<Line> {
    let mut lines = Vec::new();
    let mut body = String::new();
    let mut chars = text.chars().peekable();
    while let Some(c) = chars.next() {
        match c {
            '\r' => {
                let ending = if chars.peek() == Some(&'\n') {
                    chars.next();
                    "\r\n"
                } else {
                    "\r"
                };
                lines.push(Line {
                    body: std::mem::take(&mut body),
                    ending: ending.into(),
                });
            }
            '\n' => lines.push(Line {
                body: std::mem::take(&mut body),
                ending: "\n".into(),
            }),
            _ => body.push(c),
        }
    }
    if !body.is_empty() {
        lines.push(Line {
            body,
            ending: String::new(),
        });
    }
    lines
}

pub fn newline(lines: &[Line]) -> String {
    lines
        .iter()
        .find(|l| !l.ending.is_empty())
        .map(|l| l.ending.clone())
        .unwrap_or_else(|| "\n".into())
}

pub fn scalar(value: &serde_json::Value) -> Option<String> {
    match value {
        serde_json::Value::String(s) => Some(s.clone()),
        serde_json::Value::Number(n) => Some(n.to_string()),
        serde_json::Value::Bool(b) => Some(if *b { "True".into() } else { "False".into() }),
        _ => None,
    }
}
