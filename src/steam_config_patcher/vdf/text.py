from typing import Iterator, Optional

_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "\\": "\\"}
_UNESCAPES = {"\\": "\\\\", '"': '\\"', "\n": "\\n", "\t": "\\t", "\r": "\\r"}

_TOKEN_STRING = "string"
_TOKEN_OPEN = "open"
_TOKEN_CLOSE = "close"


class VdfSyntaxError(ValueError):
    def __init__(self, message: str, line: int):
        super().__init__(f"{message} (line {line})")
        self.line = line


class VdfNode:
    __slots__ = ("name", "value", "children")

    def __init__(
        self,
        name: Optional[str] = None,
        value: Optional[str] = None,
        children: Optional[list["VdfNode"]] = None,
    ):
        self.name = name
        self.value = value
        self.children = children

    @property
    def is_block(self) -> bool:
        return self.children is not None

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, VdfNode):
            return NotImplemented
        return (
            self.name == other.name
            and self.value == other.value
            and self.children == other.children
        )

    def __repr__(self) -> str:
        if self.is_block:
            return f"VdfNode({self.name!r}, children={self.children!r})"
        return f"VdfNode({self.name!r}, value={self.value!r})"

    def find_all(self, *key_path: str) -> Iterator["VdfNode"]:
        name, *rest = key_path
        folded = name.casefold()
        for child in self.children or []:
            if child.name.casefold() != folded:
                continue
            if not rest:
                yield child
            elif child.is_block:
                yield from child.find_all(*rest)

    def find(self, name: str) -> Optional["VdfNode"]:
        return next(self.find_all(name), None)

    def remove(self, name: str) -> bool:
        folded = name.casefold()
        remaining = [c for c in self.children if c.name.casefold() != folded]
        removed = len(remaining) != len(self.children)
        self.children[:] = remaining
        return removed

    def set_path(self, key_path: tuple[str, ...], value: str) -> None:
        *block_path, leaf_name = key_path
        node = self
        for name in block_path:
            block = next(
                (c for c in node.find_all(name) if c.is_block),
                None,
            )
            if block is None:
                block = VdfNode(name, children=[])
                node.children.append(block)
            node = block

        leaf = next((c for c in node.find_all(leaf_name) if not c.is_block), None)
        if leaf is None:
            node.children.append(VdfNode(leaf_name, value=value))
        else:
            leaf.value = value


def _read_quoted(text: str, start: int, line: int) -> tuple[str, int, int]:
    parts = []
    i = start + 1
    while i < len(text):
        c = text[i]
        if c == '"':
            return "".join(parts), i + 1, line
        if c == "\\" and i + 1 < len(text):
            escaped = text[i + 1]
            if escaped in _ESCAPES:
                parts.append(_ESCAPES[escaped])
                i += 2
                continue
        if c == "\n":
            line += 1
        parts.append(c)
        i += 1
    raise VdfSyntaxError("unterminated string", line)


def _tokenize(text: str) -> Iterator[tuple[str, Optional[str], int]]:
    i = 0
    line = 1
    length = len(text)
    while i < length:
        c = text[i]
        if c == "\n":
            line += 1
            i += 1
        elif c in " \t\r":
            i += 1
        elif c == "/" and text[i + 1 : i + 2] == "/":
            newline = text.find("\n", i)
            i = length if newline == -1 else newline
        elif c == "{":
            yield _TOKEN_OPEN, None, line
            i += 1
        elif c == "}":
            yield _TOKEN_CLOSE, None, line
            i += 1
        elif c == '"':
            start_line = line
            value, i, line = _read_quoted(text, i, line)
            yield _TOKEN_STRING, value, start_line
        else:
            start = i
            while i < length and text[i] not in ' \t\r\n{}"':
                i += 1
            yield _TOKEN_STRING, text[start:i], line


def loads(text: str) -> VdfNode:
    root = VdfNode(children=[])
    stack = [root]
    pending_key: Optional[str] = None
    line = 1

    for token_type, token_value, token_line in _tokenize(text):
        line = token_line
        if pending_key is None:
            if token_type == _TOKEN_STRING:
                pending_key = token_value
            elif token_type == _TOKEN_CLOSE:
                if len(stack) == 1:
                    raise VdfSyntaxError("unexpected '}'", token_line)
                stack.pop()
            else:
                raise VdfSyntaxError("unexpected '{'", token_line)
        else:
            if token_type == _TOKEN_STRING:
                stack[-1].children.append(VdfNode(pending_key, value=token_value))
            elif token_type == _TOKEN_OPEN:
                block = VdfNode(pending_key, children=[])
                stack[-1].children.append(block)
                stack.append(block)
            else:
                raise VdfSyntaxError(f"key {pending_key!r} has no value", token_line)
            pending_key = None

    if pending_key is not None:
        raise VdfSyntaxError(f"key {pending_key!r} has no value", line)
    if len(stack) > 1:
        raise VdfSyntaxError(f"unclosed block {stack[-1].name!r}", line)

    return root


def _escape(value: str) -> str:
    return "".join(_UNESCAPES.get(c, c) for c in value)


def _write_node(node: VdfNode, depth: int, parts: list[str]) -> None:
    indent = "\t" * depth
    if node.is_block:
        parts.append(f'{indent}"{_escape(node.name)}"\n{indent}{{\n')
        for child in node.children:
            _write_node(child, depth + 1, parts)
        parts.append(f"{indent}}}\n")
    else:
        parts.append(f'{indent}"{_escape(node.name)}"\t\t"{_escape(node.value)}"\n')


def dumps(root: VdfNode) -> str:
    parts: list[str] = []
    for child in root.children:
        _write_node(child, 0, parts)
    return "".join(parts)
