#!/usr/bin/env bash
# YouTube links the shell opens itself (its setting media.youtubeLinks): the
# link parser (src/modules/common/functions/youtube_links.js) under node, and
# the Zen extension's native host (scripts/youtube-links-host.py), kept
# running as Zen does, with a fake `nixbook-youtube-link` and the shell's
# choice file.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if command -v node >/dev/null; then
  node "$here/youtube-links-tests.js"
else
  nix-shell -p nodejs --run "node '$here/youtube-links-tests.js'"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# A fake opener: takes "take" links, says "off" for "off" links, logs them.
cat >"$tmp/open" <<'SH'
#!/usr/bin/env bash
echo "$1" >>"$(dirname "$0")/asked"
case "$1" in *take*) exit 0 ;; *off*) exit 3 ;; *) exit 1 ;; esac
SH
chmod +x "$tmp/open"

# One session with the host, as Zen keeps it: the choice it sends at start,
# a change of the choice file, then links handed over.
NIXBOOK_YOUTUBE_LINKS_CHOICE="$tmp/choice.json" python3 -I - "$here/../scripts/youtube-links-host.py" "$tmp/open" "$tmp/choice.json" <<'PY'
import json, os, struct, subprocess, sys, time

host, opener, choice = sys.argv[1:4]
p = subprocess.Popen([sys.executable, "-I", host, opener, "zen-args"], stdin=subprocess.PIPE,
                     stdout=subprocess.PIPE)
failures = 0

def expect(name, want, got):
    global failures
    if want == got:
        print(f"ok   - host: {name}")
    else:
        failures += 1
        print(f"FAIL - host: {name}: expected {want!r}, got {got!r}", file=sys.stderr)

def post(obj):
    data = json.dumps(obj).encode()
    p.stdin.write(struct.pack("=I", len(data)) + data)
    p.stdin.flush()

def read():
    raw = p.stdout.read(4)
    (n,) = struct.unpack("=I", raw)
    return json.loads(p.stdout.read(n))

expect("no shell: no choice", {"choice": None}, read())
with open(choice + ".tmp", "w") as f:
    f.write('{"enable":true,"videos":false,"music":true}\n')
os.rename(choice + ".tmp", choice)
expect("the shell's choice, when written", {"choice": {"enable": True, "videos": False, "music": True}}, read())
answers = {}
for i, url in enumerate(["https://www.youtube.com/watch?v=take0000000", "https://music.youtube.com/watch?v=no000000000",
                         "https://youtu.be/off00000000", "https://example.com/take",
                         "https://youtube.com@example.com/take"], 1):
    post({"id": i, "url": url})
for _ in range(5):
    m = read()
    answers[m["id"]] = (m["ok"], m["off"])
expect("taken", (True, False), answers[1])
expect("refused", (False, False), answers[2])
expect("off", (False, True), answers[3])
expect("not YouTube", (False, False), answers[4])
expect("user@host", (False, False), answers[5])
time.sleep(1.2)
os.remove(choice)
expect("the shell gone", {"choice": None}, read())
p.stdin.close()
expect("ends with Zen's port", 0, p.wait(timeout=5))
sys.exit(1 if failures else 0)
PY
asked=$(wc -l <"$tmp/asked" | tr -d ' ')
if [ "$asked" = 3 ]; then echo "ok   - host: only YouTube links reach the opener"; else
  echo "FAIL - host: $asked links reached the opener, not 3" >&2
  exit 1
fi
