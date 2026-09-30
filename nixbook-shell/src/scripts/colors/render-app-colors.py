#!/usr/bin/env python3
"""Render the app templates (programs.nixbook-shell.appTheming) from the
palette the shell shows: the wallpaper's or a theme variant's.

Usage: render-app-colors.py APPS_TOML < PALETTE_JSON

APPS_TOML lists the templates ([templates.<name>] input_path / output_path,
matugen's format). PALETTE_JSON maps Material roles (snake_case, e.g.
"surface_container_low") to "#rrggbb". The templates use matugen's
placeholders: {{colors.<role>.default.hex}} and .red / .green / .blue.
"""
import json
import os
import re
import sys
import tempfile
import tomllib

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


def main(apps_toml):
    # "#rrggbb", or Qt's "#aarrggbb" (alpha dropped).
    palette = {
        role: "#" + color.lstrip("#")[-6:]
        for role, color in json.load(sys.stdin).items()
        if isinstance(color, str) and re.fullmatch(r"#?([0-9A-Fa-f]{2})?[0-9A-Fa-f]{6}", color)
    }
    with open(apps_toml, "rb") as f:
        templates = tomllib.load(f).get("templates", {})
    failed = False
    for name, spec in templates.items():
        with open(spec["input_path"]) as f:
            text, missing = render(f.read(), palette)
        if missing:
            print(f"{name}: no colour for {', '.join(sorted(missing))}", file=sys.stderr)
            failed = True
            continue
        write(os.path.expanduser(spec["output_path"]), text)
    return 1 if failed else 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1]))
