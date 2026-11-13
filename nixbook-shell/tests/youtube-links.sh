#!/usr/bin/env bash
# YouTube links the shell opens itself (nixbook's youtubeLinks): the link
# parser (src/modules/common/functions/youtube_links.js) under node, and the
# Zen extension's native host (scripts/youtube-links-host.py) with a fake
# `nixbook-youtube-link`.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if command -v node >/dev/null; then
  node "$here/youtube-links-tests.js"
else
  nix-shell -p nodejs --run "node '$here/youtube-links-tests.js'"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failures=0
# A fake opener: takes the links it's told to (the shell's answer), logs the rest.
cat >"$tmp/open" <<'SH'
#!/usr/bin/env bash
echo "$1" >>"$(dirname "$0")/asked"
case "$1" in *take*) exit 0 ;; *) exit 1 ;; esac
SH
chmod +x "$tmp/open"
# ask URL → the host's answer (native messaging framing both ways).
ask() {
  python3 -I -c '
import json, struct, subprocess, sys
msg = json.dumps({"url": sys.argv[3]}).encode()
r = subprocess.run([sys.executable, "-I", sys.argv[1], sys.argv[2], "zen-args"],
                   input=struct.pack("=I", len(msg)) + msg, capture_output=True, check=True)
(n,) = struct.unpack("=I", r.stdout[:4])
print(json.dumps(json.loads(r.stdout[4:4 + n]), sort_keys=True))
' "$here/../scripts/youtube-links-host.py" "$tmp/open" "$1"
}
expect() {
  if [ "$2" = "$3" ]; then echo "ok   - $1"; else
    echo "FAIL - $1: expected $2, got $3" >&2
    failures=$((failures + 1))
  fi
}
expect "host: taken" '{"ok": true}' "$(ask 'https://www.youtube.com/watch?v=take0000000')"
expect "host: refused by the shell" '{"error": "the shell didn'"'"'t take it", "ok": false}' \
  "$(ask 'https://music.youtube.com/watch?v=no000000000')"
expect "host: not YouTube" '{"error": "not a YouTube link", "ok": false}' "$(ask 'https://example.com/take')"
expect "host: user@host" '{"error": "not a YouTube link", "ok": false}' "$(ask 'https://youtube.com@example.com/take')"
expect "host: other scheme" '{"error": "not a YouTube link", "ok": false}' "$(ask 'ftp://youtu.be/take')"
expect "host: only YouTube links reach the opener" 2 "$(wc -l <"$tmp/asked" | tr -d ' ')"
[ "$failures" -eq 0 ]
