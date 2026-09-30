#!/usr/bin/env python3
"""Render the app templates (app-templates/, the apps switched on in
Settings > Appearance) from the palette the shell shows: the wallpaper's or a
theme variant's.

Usage: render-app-colors.py TEMPLATE OUTPUT [TEMPLATE OUTPUT]... < PALETTE_JSON

PALETTE_JSON maps Material roles (snake_case, e.g. "surface_container_low")
to "#rrggbb". The templates use matugen's placeholders:
{{colors.<role>.default.hex}} and .red / .green / .blue, and {{mode}}
("light" or "dark", from the surface). Prints the outputs whose content
changed (one per line), so the caller only reloads those apps.

The apps draw these colours as text, so the palette is made readable first
(readable()): a theme variant's palette is chosen for the shell's look and may
use, say, a pastel primary that is fine as a fill but not as text on its
light surfaces. Text roles get at least 4.5:1 (WCAG AA) against every
surface they're drawn on, and each on_<role> against its <role>; a colour
that is already readable is left as it is (Material's generated palettes
are).
"""
import colorsys
import json
import os
import re
import sys
import tempfile

PLACEHOLDER = re.compile(
    r"\{\{\s*(?:colors\.([a-z_]+)\.default\.(hex|red|green|blue)|(mode))\s*\}\}"
)

# The backgrounds the apps put text on.
SURFACES = [
    "background",
    "surface",
    "surface_container_lowest",
    "surface_container_low",
    "surface_container",
    "surface_container_high",
    "surface_container_highest",
]
# Drawn as text or icons on those surfaces: minimum contrast.
TEXT_ON_SURFACES = {
    "on_background": 4.5,
    "on_surface": 4.5,
    "on_surface_variant": 4.5,
    "primary": 4.5,
    "secondary": 4.5,
    "tertiary": 4.5,
    "error": 4.5,
    "outline": 3.0,
}
# on_<role> drawn on <role> (after the fills above got their final colour).
TEXT_ON_FILL = [
    ("on_primary", "primary", 4.5),
    ("on_secondary", "secondary", 4.5),
    ("on_tertiary", "tertiary", 4.5),
    ("on_error", "error", 4.5),
    ("on_primary_container", "primary_container", 4.5),
    ("on_secondary_container", "secondary_container", 4.5),
    ("on_tertiary_container", "tertiary_container", 4.5),
    ("on_error_container", "error_container", 4.5),
    ("inverse_on_surface", "inverse_surface", 4.5),
    ("inverse_primary", "inverse_surface", 3.0),
]


def rgb(color):
    return tuple(int(color[i : i + 2], 16) / 255 for i in (1, 3, 5))


def to_hex(channels):
    return "#" + "".join(f"{round(min(max(c, 0), 1) * 255):02x}" for c in channels)


def luminance(color):
    def linear(c):
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4

    r, g, b = map(linear, rgb(color))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def is_light(color):
    # Above this, black text reads better than white.
    return luminance(color) > 0.179


def readable_on(color, backgrounds, ratio):
    """COLOR, or the nearest colour of the same hue and saturation (only its
    lightness changed) with RATIO against each of BACKGROUNDS; black or white,
    whichever reads better, when no such colour gets there."""
    def ok(c):
        return all(contrast(c, bg) >= ratio for bg in backgrounds)

    if ok(color):
        return color
    h, lightness, s = colorsys.rgb_to_hls(*rgb(color))
    for i in range(1, 101):
        for shift in (-i / 100, i / 100):
            if 0 <= lightness + shift <= 1:
                candidate = to_hex(colorsys.hls_to_rgb(h, lightness + shift, s))
                if ok(candidate):
                    return candidate
    return max(("#000000", "#ffffff"), key=lambda c: min(contrast(c, bg) for bg in backgrounds))


def readable(palette):
    palette = dict(palette)
    surfaces = [palette[r] for r in SURFACES if r in palette]
    if surfaces:
        for role, ratio in TEXT_ON_SURFACES.items():
            if role in palette:
                palette[role] = readable_on(palette[role], surfaces, ratio)
    for role, fill, ratio in TEXT_ON_FILL:
        if role in palette and fill in palette:
            palette[role] = readable_on(palette[role], [palette[fill]], ratio)
    return palette


def render(template, palette):
    missing = set()
    mode = "light" if is_light(palette.get("surface", "#ffffff")) else "dark"

    def value(match):
        role, field, is_mode = match.groups()
        if is_mode:
            return mode
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
    palette = readable({
        role: "#" + color.lstrip("#")[-6:].lower()
        for role, color in json.load(sys.stdin).items()
        if isinstance(color, str) and re.fullmatch(r"#?([0-9A-Fa-f]{2})?[0-9A-Fa-f]{6}", color)
    })
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
