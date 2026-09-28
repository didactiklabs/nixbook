#!/usr/bin/env python3
"""Check the theme registry (src/modules/common/themes.json) and print what
the login screen theme (scripts/greeter-theme.sh) needs from it, as JSON:

  {"default": "material",
   "themes": {"persona": {"variants": ["p5", ...], "default": "p5",
                          "palettes": {"p5": {"background": "#0a0a0a", ...}}}}}

The shell reads the same file (Themes.qml), so it stays the only definition
of the themes and their colours. Fails on a malformed registry: duplicate or
invalid ids, an unknown default, a palette missing a colour the theme needs."""
import json
import re
import sys

# Every palette role MaterialThemeLoader and the login screen read.
NEEDED = [
    "background", "surface1", "surface2", "surface3", "surface4",
    "onSurface", "onSurfaceVariant", "outline", "outlineVariant",
    "primary", "onPrimary", "primaryContainer", "onPrimaryContainer",
    "secondary", "onSecondary", "secondaryContainer", "onSecondaryContainer",
    "tertiary", "onTertiary", "tertiaryContainer", "onTertiaryContainer",
    "error", "onError", "errorContainer", "onErrorContainer",
    "frame", "frameBorder", "shadow", "stripe",
]
ID = re.compile(r"^[a-z][a-z0-9]*$")
COLOR = re.compile(r"^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$")


def fail(msg):
    sys.exit(f"theme-palettes: {msg}")


registry = json.load(open(sys.argv[1], encoding="utf-8"))
themes = registry.get("themes")
if not isinstance(themes, list) or not themes:
    fail("no `themes`")

out = {"default": registry.get("default"), "themes": {}}
for theme in themes:
    tid = theme.get("id", "")
    if not ID.match(tid):
        fail(f"invalid theme id {tid!r} (lowercase letters and digits: it is a settings key)")
    if tid in out["themes"]:
        fail(f"theme {tid} defined twice")
    for key in ("name", "icon"):
        if not isinstance(theme.get(key), str):
            fail(f"theme {tid} lacks `{key}`")
    variants, palettes = [], {}
    for variant in theme.get("variants", []):
        vid = variant.get("id", "")
        if not ID.match(vid) or vid in variants:
            fail(f"theme {tid}: invalid or duplicate variant id {vid!r}")
        for key in ("name", "icon"):
            if not isinstance(variant.get(key), str):
                fail(f"theme {tid}: variant {vid} lacks `{key}`")
        variants.append(vid)
        palette = variant.get("palette")
        if palette is None:
            continue
        missing = [k for k in NEEDED if k not in palette]
        if missing:
            fail(f"{tid}/{vid} palette lacks {', '.join(missing)}")
        bad = [k for k, v in palette.items() if not (isinstance(v, str) and COLOR.match(v))]
        if bad:
            fail(f"{tid}/{vid} palette: not a #rrggbb colour: {', '.join(bad)}")
        palettes[vid] = palette
    default = theme.get("defaultVariant", variants[0] if variants else None)
    if variants and default not in variants:
        fail(f"theme {tid}: defaultVariant {default!r} is not one of its variants")
    out["themes"][tid] = {"variants": variants, "default": default, "palettes": palettes}

if out["default"] not in out["themes"]:
    fail(f"default theme {out['default']!r} is not defined")

json.dump(out, sys.stdout, indent=2)
print()
