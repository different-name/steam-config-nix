import re

_SECTION = re.compile(r"^\s*\[(?P<name>[^]\r\n]*)]\s*(?:[;#].*)?$")
_HEADERISH = re.compile(r"^\s*\[")
_COMMENT = re.compile(r"^\s*[;#]")
_ENTRY = re.compile(r"^(?P<prefix>(?P<indent>\s*)(?P<key>[^\s;#=][^=]*?)\s*=\s*)(?P<value>.*)$")
_ENDING = re.compile(r"\r\n|\n|\r")

# the utf-32 marks start with the utf-16 ones, so the longer prefix has to be tried first
_BOMS = (
    (b"\x00\x00\xfe\xff", "utf-32-be"),
    (b"\xff\xfe\x00\x00", "utf-32-le"),
    (b"\xef\xbb\xbf", "utf-8"),
    (b"\xff\xfe", "utf-16-le"),
    (b"\xfe\xff", "utf-16-be"),
)


def _sniff_wide(data: bytes) -> str:
    # windows writes utf-16 without a mark, and reading those bytes as utf-8 corrupts the file
    even = any(byte == 0 for byte in data[0::2])
    odd = any(byte == 0 for byte in data[1::2])
    if odd and not even:
        return "utf-16-le"
    if even and not odd:
        return "utf-16-be"
    raise ValueError("the file is not text we can edit as ini")


def _decode(data: bytes) -> tuple[str, str, bytes]:
    for bom, codec in _BOMS:
        if data.startswith(bom):
            return data[len(bom) :].decode(codec), codec, bom
    if b"\x00" in data:
        codec = _sniff_wide(data)
        return data.decode(codec), codec, b""
    return data.decode("utf-8", errors="surrogateescape"), "utf-8", b""


def _split(text: str) -> list[tuple[str, str]]:
    lines: list[tuple[str, str]] = []
    position = 0
    for match in _ENDING.finditer(text):
        lines.append((text[position : match.start()], match.group()))
        position = match.end()
    if position < len(text):
        lines.append((text[position:], ""))
    return lines


def _check(line: str, section: object, key: object, rendered: str) -> None:
    written = _ENTRY.match(line)
    if (
        written is None
        or written.group("key") != str(key)
        or written.group("value") != rendered
    ):
        raise ValueError(f"{section}.{key} cannot be written as an ini value")


def _renderings(section: object, key: object, value: object) -> list[str]:
    if isinstance(value, (list, tuple)):
        return [rendering for item in value for rendering in _renderings(section, key, item)]
    if value is None or isinstance(value, dict):
        raise ValueError(f"{section}.{key} is not a value an ini file can hold")
    rendered = str(value)
    # a line ending in a value splits the line, and the halves grow the file on every run
    if _ENDING.search(rendered):
        raise ValueError(f"{section}.{key} cannot be written as an ini value")
    return [rendered]


def _scan(lines: list[tuple[str, str]]) -> tuple[dict[tuple[str, str], list[int]], dict[str, int]]:
    # a key can appear more than once, which is how unreal writes list valued settings
    entries: dict[tuple[str, str], list[int]] = {}
    section_end: dict[str, int] = {}
    current = ""
    previous_indent: str | None = None
    structured = False

    for index, (body, _) in enumerate(lines):
        if not body.strip():
            continue
        if _COMMENT.match(body):
            continue
        header = _SECTION.match(body)
        if header is not None:
            current = header.group("name").strip()
            section_end[current] = index
            previous_indent = None
            structured = True
            continue
        # an unparsed header would put the keys under it into the section above
        if _HEADERISH.match(body):
            raise ValueError(f"{body.strip()} is not a section header we can edit around")
        section_end[current] = index
        entry = _ENTRY.match(body)
        if entry is None:
            previous_indent = None
            continue
        # configparser folded a deeper indented line into the value above, so it is not ours to edit
        indent = entry.group("indent")
        if previous_indent is not None and len(indent) > len(previous_indent):
            raise ValueError(f"{body.strip()} continues the line above it")
        previous_indent = indent
        structured = True
        entries.setdefault((current, entry.group("key")), []).append(index)

    if not structured and any(body.strip() for body, _ in lines):
        raise ValueError("the file has no ini sections or keys to merge into")
    return entries, section_end


def apply(content: dict, existing: bytes) -> bytes:
    text, codec, bom = _decode(existing)
    lines = _split(text)
    newline = next((ending for _, ending in lines if ending), "\n")
    entries, section_end = _scan(lines)

    dropped: set[int] = set()
    inserted: dict[int, list[str]] = {}
    new_sections: dict[str, list[str]] = {}

    for section, values in content.items():
        if not isinstance(values, dict):
            raise ValueError(f"{section} is not a table of ini keys")
        for key, value in values.items():
            renderings = _renderings(section, key, value)
            found = entries.get((str(section), str(key))) or []
            for position, rendered in enumerate(renderings):
                if position < len(found):
                    body, ending = lines[found[position]]
                    previous = _ENTRY.match(body)
                    assert previous is not None
                    # a value that does not read back splits the line and forges a section on every run
                    updated = previous.group("prefix") + rendered
                    _check(updated, section, key, rendered)
                    lines[found[position]] = (updated, ending)
                    continue
                line = f"{key}={rendered}"
                # a key we cannot read back would be appended again on every run
                _check(line, section, key, rendered)
                if found:
                    inserted.setdefault(found[-1], []).append(line)
                elif str(section) in section_end:
                    inserted.setdefault(section_end[str(section)], []).append(line)
                else:
                    # a header we cannot read back never matches, so the section would be appended again every run
                    header = _SECTION.match(f"[{section}]")
                    if header is None or header.group("name").strip() != str(section):
                        raise ValueError(f"{section} cannot be written as an ini section")
                    new_sections.setdefault(str(section), []).append(line)
            # a patched key ends up with exactly as many occurrences as it has values
            dropped.update(found[len(renderings) :])

    out: list[str] = []

    def terminate() -> None:
        if out and not out[-1].endswith(("\n", "\r")):
            out[-1] += newline

    for index, (body, ending) in enumerate(lines):
        if index not in dropped:
            out.append(body + ending)
        extra = inserted.get(index)
        if extra is not None:
            terminate()
            out.extend(line + newline for line in extra)

    for section, added in new_sections.items():
        terminate()
        if out:
            out.append(newline)
        out.append(f"[{section}]" + newline)
        out.extend(line + newline for line in added)

    return bom + "".join(out).encode(codec, errors="surrogateescape")
