#!/usr/bin/env python3
"""Merge a KDE colour scheme into kdeglobals: its [Colors:*],
[ColorEffects:*] and [WM] sections replace the ones there, and the scheme is
named in [General] / [UiSettings] ColorScheme (what KDE apps such as Dolphin
load). Every other section and key of kdeglobals is left as it is.

Usage: apply-kde-colors.py SCHEME KDEGLOBALS
"""
import os
import re
import sys
import tempfile

SCHEME_NAME = "NixbookShell"
COLOR_SECTION = re.compile(r"^\[(Colors:|ColorEffects:|WM\])")


def sections(text):
    """[(header or None, [lines])], in order; header None: before any section."""
    out = [(None, [])]
    for line in text.splitlines():
        if line.startswith("["):
            out.append((line.strip(), []))
        else:
            out[-1][1].append(line)
    return out


def set_key(parsed, header, key, value):
    for h, lines in parsed:
        if h == header:
            for i, line in enumerate(lines):
                if line.split("=", 1)[0].strip() == key:
                    lines[i] = f"{key}={value}"
                    return
            # Before the section's trailing blank lines.
            at = len(lines)
            while at > 0 and not lines[at - 1].strip():
                at -= 1
            lines.insert(at, f"{key}={value}")
            return
    parsed.append((header, [f"{key}={value}", ""]))


def render(parsed):
    out = []
    for header, lines in parsed:
        if header is not None:
            out.append(header)
        out.extend(lines)
    return "\n".join(out).rstrip("\n") + "\n"


def main(scheme_path, kdeglobals_path):
    with open(scheme_path) as f:
        scheme = [s for s in sections(f.read()) if s[0] and COLOR_SECTION.match(s[0])]
    try:
        with open(kdeglobals_path) as f:
            current = sections(f.read())
    except FileNotFoundError:
        current = [(None, [])]

    merged = [s for s in current if not (s[0] and COLOR_SECTION.match(s[0]))]
    for header, lines in scheme:
        lines = [l for l in lines if l.strip()] + [""]
        merged.append((header, lines))
    set_key(merged, "[General]", "ColorScheme", SCHEME_NAME)
    set_key(merged, "[UiSettings]", "ColorScheme", SCHEME_NAME)

    directory = os.path.dirname(kdeglobals_path) or "."
    os.makedirs(directory, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".kdeglobals.")
    with os.fdopen(fd, "w") as f:
        f.write(render(merged))
    os.chmod(tmp, 0o644)
    os.replace(tmp, kdeglobals_path)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
