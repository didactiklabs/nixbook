#!/usr/bin/env python3
"""Render the app templates (app-templates/, the apps switched on in
Settings > Appearance) from the palette the shell shows: the wallpaper's or a
theme variant's.

Usage: render-app-colors.py TEMPLATE OUTPUT [TEMPLATE OUTPUT]... < PALETTE_JSON

PALETTE_JSON maps Material roles (snake_case, e.g. "surface_container_low")
to "#rrggbb". The templates use matugen's placeholders:
{{colors.<role>.default.hex}} and .red / .green / .blue. Prints the outputs
whose content changed (one per line), so the caller only reloads those apps.
"""
import json
import os
import re
import sys
import tempfile

PLACEHOLDER = re.compile(r"\{\{\s*colors\.([a-z_]+)\.default\.(hex|red|green|blue)\s*\}\}")


def render(template, palette):
    missing = set()

    def value(match):
        role, field = match.groups()
        color = palette.get(role)
        if color is None:
            missing.add(role)
            return match.group(0)
        if field == "hex":
            return color.lower()
        channel = {"red": 1, "green": 3, "blue": 5}[field]
        return str(int(color[channel : channel + 2], 16))

    return PLACEHOLDER.sub(value, template), missing


def write(path, text):
    directory = os.path.dirname(path) or "."
    os.makedirs(directory, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".nixbook-shell.")
    with os.fdopen(fd, "w") as f:
        f.write(text)
    os.chmod(tmp, 0o644)
    os.replace(tmp, path)


def main(pairs):
    # "#rrggbb", or Qt's "#aarrggbb" (alpha dropped).
    palette = {
        role: "#" + color.lstrip("#")[-6:]
        for role, color in json.load(sys.stdin).items()
        if isinstance(color, str) and re.fullmatch(r"#?([0-9A-Fa-f]{2})?[0-9A-Fa-f]{6}", color)
    }
    failed = False
    for template, output in pairs:
        with open(template) as f:
            text, missing = render(f.read(), palette)
        if missing:
            print(f"{template}: no colour for {', '.join(sorted(missing))}", file=sys.stderr)
            failed = True
            continue
        output = os.path.expanduser(output)
        try:
            with open(output) as f:
                if f.read() == text:
                    continue
        except OSError:
            pass
        write(output, text)
        print(output)
    return 1 if failed else 0


if __name__ == "__main__":
    args = sys.argv[1:]
    if not args or len(args) % 2:
        sys.exit(__doc__)
    sys.exit(main(list(zip(args[::2], args[1::2]))))
