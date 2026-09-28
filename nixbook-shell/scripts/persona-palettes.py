#!/usr/bin/env python3
"""Print the Persona palettes of src/modules/common/Persona.qml (its `specs`)
as JSON: {"p5": {"background": "#0a0a0a", ...}, ...}. The login screen theme
(scripts/greeter-theme.sh) is built from them, so the shell stays their only
definition. Fails if a variant or a colour the theme needs is missing."""
import json
import re
import sys

NEEDED = [
    "background", "surface1", "surface2", "surface3", "surface4",
    "onSurface", "onSurfaceVariant", "outline", "outlineVariant",
    "primary", "onPrimary", "primaryContainer", "onPrimaryContainer",
    "secondaryContainer", "onSecondaryContainer",
    "error", "errorContainer", "onErrorContainer",
    "frame", "frameBorder", "shadow", "stripe",
]

src = open(sys.argv[1], encoding="utf-8").read()
specs = re.search(r"property var specs: \(\{(.*?)\n    \}\)", src, re.S)
if not specs:
    sys.exit("persona-palettes: no `specs` in " + sys.argv[1])

palettes = {}
for m in re.finditer(r'"(p\w+)":\s*\{(.*?)\n        \}', specs.group(1), re.S):
    palettes[m.group(1)] = dict(re.findall(r'(\w+):\s*"(#[0-9a-fA-F]{6,8})"', m.group(2)))

for variant in ("p5", "p3r", "p4"):
    missing = [k for k in NEEDED if k not in palettes.get(variant, {})]
    if missing:
        sys.exit(f"persona-palettes: {variant} lacks {', '.join(missing)}")

json.dump(palettes, sys.stdout, indent=2, sort_keys=True)
print()
