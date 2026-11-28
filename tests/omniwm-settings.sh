#!/usr/bin/env bash
# homeManagerModules/omniwm/apply-settings.py: the Nix keys and hotkeys go into
# OmniWM's settings.toml, everything else stays, nothing is written twice.
#   tests/omniwm-settings.sh            (tests/run.sh darwin runs it)
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python=$(nix-build --no-out-link -E \
  "with import $repo/lib/pkgs.nix { }; python3.withPackages (ps: [ ps.tomli-w ])")/bin/python3
apply="$repo/homeManagerModules/omniwm/apply-settings.py"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failed=0

ok() { echo "ok   - $1"; }
fail() {
  echo "FAIL - $1" >&2
  failed=1
}

cat >"$tmp/pinned.json" <<'EOF'
{
  "settings": {
    "gaps": { "size": 10 },
    "general": { "updateChecksEnabled": false },
    "niri": { "defaultContainerPrimarySpan": 0.8 }
  },
  "hotkeys": {
    "openApp.net.kovidgoyal.kitty": "Option+Return",
    "toggleFullscreen": "Option+F",
    "toggleOverview": "Option+Tab",
    "focus.left": "Option+Left Arrow",
    "noSuchAction": "Option+X"
  }
}
EOF

# No file yet (OmniWM never started): nothing written, exit 0.
"$python" "$apply" "$tmp/pinned.json" "$tmp/settings.toml" 2>"$tmp/err"
if [ ! -e "$tmp/settings.toml" ] && grep -q "doesn't exist yet" "$tmp/err"; then
  ok "no settings.toml yet: left for OmniWM to write"
else
  fail "a missing settings.toml was created or not reported"
fi

cat >"$tmp/settings.toml" <<'EOF'
schemaVersion = 5

[general]
hotkeysEnabled = true
updateChecksEnabled = true

[gaps]
size = 16.0
fullscreenUsesOuterGaps = false

[niri]
visibleContainerCount = 2

[[hotkeys]]
binding = "Option+Return"
id = "toggleFullscreen"

[[hotkeys]]
binding = "Option+Tab"
id = "focusPrevious"

[[hotkeys]]
binding = "Option+Shift+O"
id = "toggleOverview"

[[hotkeys]]
binding = "Option+Left Arrow"
id = "focus.left"
EOF
cp "$tmp/settings.toml" "$tmp/original.toml"

"$python" "$apply" "$tmp/pinned.json" "$tmp/settings.toml" 2>"$tmp/err"
if "$python" - "$tmp/settings.toml" <<'EOF'
import sys, tomllib
d = tomllib.load(open(sys.argv[1], "rb"))
hk = {e["id"]: e["binding"] for e in d["hotkeys"]}
assert d["schemaVersion"] == 5
assert d["gaps"] == {"size": 10.0, "fullscreenUsesOuterGaps": False}, d["gaps"]
assert isinstance(d["gaps"]["size"], float), "10 from JSON must stay a float"
assert d["general"] == {"hotkeysEnabled": True, "updateChecksEnabled": False}
assert d["niri"] == {"visibleContainerCount": 2, "defaultContainerPrimarySpan": 0.8}
assert hk["toggleFullscreen"] == "Option+F", hk
assert hk["openApp.net.kovidgoyal.kitty"] == "Option+Return", hk
assert hk["toggleOverview"] == "Option+Tab", hk
assert hk["focusPrevious"] == "Unassigned", "the action on a chord Nix takes is unassigned"
assert hk["focus.left"] == "Option+Left Arrow"
assert "noSuchAction" not in hk, "an unknown action must not be added"
EOF
then
  ok "keys merged table by table, hotkeys moved, chords freed, float kept"
else
  fail "merged settings.toml is wrong:"
  cat "$tmp/settings.toml" >&2
fi
if grep -q "noSuchAction" "$tmp/err"; then ok "an unknown action is reported"; else fail "unknown action not reported"; fi
if cmp -s "$tmp/settings.toml.before-nixbook" "$tmp/original.toml"; then
  ok "the first version is kept as settings.toml.before-nixbook"
else
  fail "no backup of the original"
fi

# Applied twice: not rewritten (the launchd agent runs on every change).
before=$(stat -c %Y.%i "$tmp/settings.toml" 2>/dev/null || stat -f %m.%i "$tmp/settings.toml")
sleep 1
"$python" "$apply" "$tmp/pinned.json" "$tmp/settings.toml" 2>/dev/null
after=$(stat -c %Y.%i "$tmp/settings.toml" 2>/dev/null || stat -f %m.%i "$tmp/settings.toml")
if [ "$before" = "$after" ]; then ok "nothing to change: the file isn't rewritten"; else fail "rewritten with no change"; fi

# Unreadable TOML: left alone.
printf 'not = [toml\n' >"$tmp/bad.toml"
cp "$tmp/bad.toml" "$tmp/bad.orig"
"$python" "$apply" "$tmp/pinned.json" "$tmp/bad.toml" 2>/dev/null
if cmp -s "$tmp/bad.toml" "$tmp/bad.orig"; then ok "an unreadable file is left alone"; else fail "an unreadable file was changed"; fi

exit "$failed"
