import json
import re
import sys
from pathlib import Path

ROOT = "programs.steam.config"

SEGMENT = re.compile(r'\.(?:"([^"\n]*)"|([A-Za-z0-9_-]+))')
# concrete attr names in the docs stand in for the <name> placeholder
PLACEHOLDER = re.compile(r'^(?:"[^"]*"|[0-9]+)$')


def parse_paths(text):
    for start in (m.end() for m in re.finditer(re.escape(ROOT), text)):
        segments = []
        pos = start
        while match := SEGMENT.match(text, pos):
            quoted, bare = match.groups()
            segments.append(f'"{quoted}"' if quoted is not None else bare)
            pos = match.end()
        if segments:
            yield ROOT + "." + ".".join(segments), segments


def normalise(segments, attr_parents):
    out = []
    for segment in segments:
        prefix = ROOT + "".join(f".{s}" for s in out)
        if prefix in attr_parents and PLACEHOLDER.match(segment):
            out.append("<name>")
        else:
            out.append(segment)
    return ROOT + "." + ".".join(out)


def freeform_prefix(path, freeform):
    parts = path.split(".")
    for cut in range(len(parts) - 1, 0, -1):
        if ".".join(parts[:cut]) in freeform:
            return True
    return False


def main(options_json, content_dir):
    options = json.loads(Path(options_json).read_text())

    known = set(options)
    attr_parents = {
        name
        for name, opt in options.items()
        if "attribute set" in opt.get("type", "")
    }
    # apps/nonSteamApps declare real options under <name>, so those are not freeform
    freeform = {
        name
        for name in attr_parents
        if not any(other.startswith(f"{name}.<name>.") for other in known)
    }

    failures = []
    for page in sorted(Path(content_dir).rglob("*.md")):
        for raw, segments in parse_paths(page.read_text()):
            path = normalise(segments, attr_parents)
            # a page can name apps.<name> before setting anything on it
            branch = any(other.startswith(f"{path}.") for other in known)
            if path in known or branch or freeform_prefix(path, freeform):
                continue
            failures.append(f"{page.relative_to(content_dir)}: {raw}")

    if failures:
        print("docs reference options that do not exist:\n", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        print(
            "\nrename them to match the module, or remove them.",
            file=sys.stderr,
        )
        return 1

    print(f"checked {len(known)} options against {content_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
