import re
from collections.abc import Callable
from dataclasses import dataclass

_SECTION_RE = re.compile(r"^\[(.*?)\]")


@dataclass
class Section:
    path: str
    header_line: str
    body: list[str]


def escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def read_quoted(text: str, start: int) -> tuple[str | None, int]:
    parts: list[str] = []
    i = start + 1
    while i < len(text):
        c = text[i]
        if c == "\\" and i + 1 < len(text):
            parts.append(text[i + 1])
            i += 2
            continue
        if c == '"':
            return "".join(parts), i + 1
        parts.append(c)
        i += 1
    return None, i


def _value_name(line: str) -> str | None:
    stripped = line.strip()
    if stripped.startswith("@="):
        return "@"
    if not stripped.startswith('"'):
        return None
    name, end = read_quoted(stripped, 0)
    if name is None or stripped[end : end + 1] != "=":
        return None
    return name


def _join_continuations(lines: list[str]) -> list[str]:
    result: list[str] = []
    buffer: list[str] | None = None
    for line in lines:
        if buffer is not None:
            buffer.append(line)
            if not line.endswith("\\"):
                result.append("\n".join(buffer))
                buffer = None
            continue
        if line.endswith("\\"):
            buffer = [line]
        else:
            result.append(line)
    if buffer is not None:
        result.append("\n".join(buffer))
    return result


def _parse(text: str) -> tuple[list[str], list[Section]]:
    header: list[str] = []
    sections: list[Section] = []
    current: Section | None = None
    for line in _join_continuations(text.split("\n")):
        match = _SECTION_RE.match(line)
        if match is not None:
            current = Section(
                path=match.group(1).replace("\\\\", "\\"),
                header_line=line,
                body=[],
            )
            sections.append(current)
        elif current is None:
            header.append(line)
        else:
            current.body.append(line)
    return header, sections


def put_line(section: Section, name: str, new_line: str) -> None:
    for i, line in enumerate(section.body):
        if _value_name(line) == name:
            section.body[i] = new_line
            return
    insert_at = len(section.body)
    while insert_at > 0 and section.body[insert_at - 1] == "":
        insert_at -= 1
    section.body.insert(insert_at, new_line)


def apply(
    content: dict,
    existing: bytes,
    set_value: Callable[[Section, str, object], None],
) -> bytes:
    text = (
        existing.decode("utf-8")
        if existing.strip()
        else "WINE REGISTRY Version 2\n\n"
    )
    header, sections = _parse(text)
    for path, values in content.items():
        section = next((s for s in sections if s.path == path), None)
        if section is None:
            tail = sections[-1].body if sections else header
            if not tail or tail[-1] != "":
                tail.append("")
            section = Section(
                path=path,
                header_line="[" + path.replace("\\", "\\\\") + "]",
                body=[],
            )
            sections.append(section)
        for key, value in values.items():
            set_value(section, key, value)
    lines = list(header)
    for section in sections:
        lines.append(section.header_line)
        lines.extend(section.body)
    out = "\n".join(lines)
    if not out.endswith("\n"):
        out += "\n"
    return out.encode("utf-8")
