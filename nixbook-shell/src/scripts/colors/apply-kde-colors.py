#!/usr/bin/env python3
"""Merge a KDE colour scheme into kdeglobals: its [Colors:*],
[ColorEffects:*] and [WM] sections replace the ones there, and the scheme is
named in [General] / [UiSettings] ColorScheme (what KDE apps such as Dolphin
load). Every other section and key of kdeglobals is left as it is.

Usage: apply-kde-colors.py SCHEME KDEGLOBALS
       apply-kde-colors.py --unpin APPRC...

--unpin: a KDE app can pin its own colour scheme in its rc file ([UiSettings]
ColorScheme, written by Dolphin's View > Color Scheme menu), which wins over
kdeglobals. A pin naming another scheme (e.g. DankMatugen, left by
DankMaterialShell) is removed so the app follows the shell's colours: mixed
with the palette qt6ct applies, a dark pinned scheme drew dark text on dark
rows. Prints the files changed.
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


def write(path, text):
    directory = os.path.dirname(path) or "."
    os.makedirs(directory, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".nixbook-shell.")
    with os.fdopen(fd, "w") as f:
        f.write(text)
    os.chmod(tmp, 0o644)
    os.replace(tmp, path)


def unpin(rc_path):
    try:
        with open(rc_path) as f:
            parsed = sections(f.read())
    except (OSError, UnicodeDecodeError):
        return False
    changed = False
    for header, lines in parsed:
        if header != "[UiSettings]":
            continue
        kept = [
            l for l in lines
            if not (l.split("=", 1)[0].strip() == "ColorScheme" and l.split("=", 1)[-1].strip() != SCHEME_NAME)
        ]
        if len(kept) != len(lines):
            lines[:] = kept
            changed = True
    if changed:
        # Drop a [UiSettings] left empty.
        parsed = [(h, l) for h, l in parsed if not (h == "[UiSettings]" and not any(x.strip() for x in l))]
        write(rc_path, render(parsed))
    return changed


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

    write(kdeglobals_path, render(merged))


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "--unpin":
        for rc in sys.argv[2:]:
            if unpin(rc):
                print(rc)
        sys.exit(0)
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
