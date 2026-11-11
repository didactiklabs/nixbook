"""Meru with its Pro features on, for nixbook (its code is AGPL-3.0).

Runs on the unpacked app (resources/app/build-js): the main process
(app.js) and the settings window (renderer/assets/main-*.js). Every Pro
feature checks one flag, the licence class's `isValid`, and the settings
window turns a Pro setting on when a licence key is stored:

  - the licence's `validate()` says valid at once (no licence server asked),
    and `init()` stores a placeholder key when there is none;
  - the trial isn't checked then (it is skipped when the licence is valid):
    no trial banner, no upgrade dialogs;
  - Meru's own updater is off (a Nix-built app can't update itself; npins
    bumps the pinned release);
  - the settings window's License and Updates pages are gone.

The patterns match the code's shape, not the bundler's names (which change
from one release to the next). Each must match exactly once: when a release
changes that code, the build stops here, and this script needs updating.

    python3 unlock.py APP_DIR [ELECTRON_BINARY]
"""

import glob
import os
import re
import sys

app = sys.argv[1]
build = os.path.join(app, "build-js")

# (file glob, what it does, pattern, replacement)
PATCHES = [
    ("app.js", "the licence is valid from the start, a placeholder key stored",
     r"new class\{isValid=!1;init\(\)\{let (\w+)=process\.env\.MERU_LICENSE_KEY\|\|null;\1&&([\w$]+)\.get\(`licenseKey`\)"
     r"!==\1&&\2\.set\(`licenseKey`,\1\)\}",
     r"new class{isValid=!0;init(){\2.get(`licenseKey`)||\2.set(`licenseKey`,`nixbook`)}"),
    ("app.js", "validating the licence asks no server",
     r"async validate\(\{useFallback:(\w+)\}=\{\}\)\{let (\w+)=([\w$]+)\.get\(`licenseKey`\);if\(!\2\)return!0;",
     r"async validate(){return this.isValid=!0,!0}"
     r"async upstreamValidate({useFallback:\1}={}){let \2=\3.get(`licenseKey`);if(!\2)return!0;"),
    ("app.js", "Meru's own updater never checks",
     r"([\w$]+)\.dev\|\|!([\w$]+)\.get\(`updates\.autoCheck`\)\|\|\(this\.requestUpdateCheck\(\)",
     r"\1.dev||!0||(this.requestUpdateCheck()"),
    ("renderer/assets/main-*.js", "no License page in the settings",
     r"\{label:[\w$]+\.license,path:`/settings/license`,component:[\w$]+\},", ""),
    ("renderer/assets/main-*.js", "no Updates page in the settings",
     r"\{label:[\w$]+\.updates,path:`/settings/updates`,component:[\w$]+\},", ""),
]

failed = []
for pattern_glob, what, pattern, replacement in PATCHES:
    files = glob.glob(os.path.join(build, pattern_glob))
    hits = []
    for path in files:
        with open(path, encoding="utf-8") as f:
            text = f.read()
        n = len(re.findall(pattern, text))
        if n:
            hits.append((path, text, n))
    if len(hits) != 1 or hits[0][2] != 1:
        found = ", ".join(f"{os.path.relpath(p, build)}×{n}" for p, _, n in hits) or "nowhere"
        failed.append(f"{what}: the pattern should match once, it matches {found}")
        continue
    path, text, _ = hits[0]
    with open(path, "w", encoding="utf-8") as f:
        f.write(re.sub(pattern, replacement, text))
    print(f"meru unlock: {what}")

if failed:
    sys.exit("meru unlock: this Meru release changed the code patched:\n  " + "\n  ".join(failed))

# Electron's fuses: Meru's build only loads its app from app.asar and checks
# that file's integrity, which refuses the patched, unpacked one. The two
# switched off, as @electron/fuses does (the sentinel, a version byte, the
# count, then one byte per fuse: "0" off, "1" on).
FUSE_SENTINEL = b"dL7pKGdnNz796PbbjQWNKmHXBZaB9tsX"
FUSES_OFF = {4: "EnableEmbeddedAsarIntegrityValidation", 5: "OnlyLoadAppFromAsar"}
if len(sys.argv) > 2:
    binary = sys.argv[2]
    with open(binary, "rb") as f:
        data = bytearray(f.read())
    at = data.find(FUSE_SENTINEL)
    if at < 0 or data.find(FUSE_SENTINEL, at + 1) >= 0 or data[at + 32] != 1:
        sys.exit("meru unlock: Electron's fuses aren't where they were (version 1, once)")
    count = data[at + 33]
    for index, name in FUSES_OFF.items():
        pos = at + 34 + index
        if index >= count or data[pos] not in b"01":
            sys.exit(f"meru unlock: no {name} fuse")
        data[pos] = ord("0")
        print(f"meru unlock: Electron fuse {name} off")
    with open(binary, "wb") as f:
        f.write(data)
