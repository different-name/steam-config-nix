def _leading_token(line: str) -> str | None:
    stripped = line.lstrip()
    if not stripped or stripped.startswith("//"):
        return None
    return stripped.split(None, 1)[0]


def _split_value(remainder: str) -> tuple[str, str]:
    n = len(remainder)
    if n and remainder[0] == '"':
        j = 1
        while j < n and remainder[j] != '"':
            j += 1
        if j < n:
            j += 1
        return remainder[:j], remainder[j:]
    j = 0
    while j < n and not remainder[j].isspace() and remainder[j : j + 2] != "//":
        j += 1
    return remainder[:j], remainder[j:]


def _render_value(value: object) -> str:
    if isinstance(value, bool):
        return "1" if value else "0"
    return str(value)


def _rewrite(line: str, new_value: str) -> str:
    indent = line[: len(line) - len(line.lstrip())]
    stripped = line[len(indent) :]
    name = stripped.split(None, 1)[0]
    after = stripped[len(name) :]
    sep = after[: len(after) - len(after.lstrip())]
    _, rest = _split_value(after[len(sep) :])
    return f'{indent}{name}{sep}"{new_value}"{rest}'


def render(content: dict, existing: bytes) -> bytes:
    text = existing.decode("utf-8") if existing.strip() else ""
    newline = "\r\n" if "\r\n" in text else "\n"
    raw = text.split("\n")
    if raw and raw[-1] == "":
        raw.pop()
    lines = [ln[:-1] if ln.endswith("\r") else ln for ln in raw]

    targets = {name.lower(): name for name in content}
    last_index: dict[str, int] = {}
    for i, line in enumerate(lines):
        token = _leading_token(line)
        if token is not None and token.lower() in targets:
            last_index[token.lower()] = i

    for key, i in last_index.items():
        lines[i] = _rewrite(lines[i], _render_value(content[targets[key]]))

    for name in content:
        if name.lower() not in last_index:
            lines.append(f'{name} "{_render_value(content[name])}"')

    out = newline.join(lines)
    if out and not out.endswith("\n"):
        out += newline
    return out.encode("utf-8")
