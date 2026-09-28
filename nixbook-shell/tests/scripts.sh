#!/usr/bin/env bash
# Tests for the nixbook-shell helper scripts (scripts/):
#   - config-merge.jq: the JSON -> Nix printers must round-trip through Nix;
#   - config-tool.sh: `nixbook-shell config diff|pinned|dump|path` on fixtures;
#   - assistant-facts.py: fact file structure, keybind and Neovim keymap descriptions.
# Needs bash, jq, python3 and nix-instantiate. Run: bash tests/scripts.sh
# The jq programs are single-quoted on purpose: `$n`, `$a`, ... are jq variables.
# shellcheck disable=SC2016
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scripts="$root/scripts"
builtin="$root/builtin-defaults.json"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

failures=0
pass() { echo "ok   - $1"; }
fail() {
  echo "FAIL - $1" >&2
  [ $# -lt 2 ] || printf '%s\n' "$2" | sed 's/^/       /' >&2
  failures=$((failures + 1))
}
# expect_eq NAME EXPECTED ACTUAL
expect_eq() {
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected: $2"$'\n'"actual:   $3"; fi
}
# expect_contains NAME HAYSTACK NEEDLE
expect_contains() {
  if grep -qF -- "$3" <<<"$2"; then pass "$1"; else fail "$1" "missing: $3"$'\n'"in:"$'\n'"$2"; fi
}

mergejq() { jq -L "$scripts" "$@"; }
# JSON of a Nix expression read from stdin.
nix_to_json() { nix-instantiate --eval --strict --json --expr "$(cat)"; }
# Same JSON value (numbers compared numerically, key order ignored)?
same_json() { jq -en --argjson a "$1" --argjson b "$2" '$a == $b' >/dev/null; }

# -- config-merge.jq: JSON -> Nix printers -------------------------------------

cat >"$tmp/tricky.json" <<'EOF'
{
  "plain": "text",
  "quotes": "say \"hi\"",
  "backslash": "C:\\path\\",
  "interpolation": "${HOME} and $HOME and ''${x}",
  "newline": "a\nb",
  "unicode": "Tiếng Việt – ü",
  "negative": -1,
  "negList": [1, -1, -2.5],
  "float": 0.25,
  "zero": 0,
  "bools": [true, false],
  "null": null,
  "emptyObj": {},
  "emptyList": [],
  "nested": {"a": {"b": [[], [{}], ["x", {"y": null}]]}},
  "dotted.key": 1,
  "1starts-with-digit": 2,
  "with space": 3,
  "has'quote-and-dash_ok": 4,
  "": "empty key"
}
EOF

for fixture in "$tmp/tricky.json" "$builtin"; do
  name=$(basename "$fixture")
  for printer in 'tonix' 'nixpp("")'; do
    if nix=$(mergejq -r "include \"config-merge\"; $printer" "$fixture") &&
      back=$(nix_to_json <<<"$nix" 2>"$tmp/err") &&
      same_json "$(cat "$fixture")" "$back"; then
      pass "config-merge.jq $printer round-trips $name through Nix"
    else
      fail "config-merge.jq $printer round-trips $name through Nix" "$(cat "$tmp/err" 2>/dev/null)"
    fi
  done
done

leaves=$(mergejq -c 'include "config-merge"; [leaves]' <<<'{"a":{"b":1,"c":{}},"d":[1],"e":{"f":{"g":null}}}')
expect_eq "config-merge.jq leaves: lists and empty objects are leaves" \
  '[["a","b"],["a","c"],["d"],["e","f","g"]]' "$leaves"
expect_eq "config-merge.jq at: missing or mistyped path is null" \
  '[1,null,null]' "$(mergejq -c 'include "config-merge"; [at(["a","b"]), at(["a","x"]), at(["a","b","c"])]' <<<'{"a":{"b":1}}')"
expect_eq "config-merge.jq nixline quotes non-identifier keys" \
  'bar."dotted.key".x-y = [ 1 (-2) "s" ];' \
  "$(mergejq -r 'include "config-merge"; nixline(["bar","dotted.key","x-y"]; [1,-2,"s"])' <<<'null')"

# -- config-tool.sh: `nixbook-shell config` ------------------------------------

export XDG_CONFIG_HOME="$tmp/config"
cfg="$XDG_CONFIG_HOME/nixbook-shell"
mkdir -p "$cfg"
export NIXBOOK_SHELL_MERGE_JQ="$scripts/config-merge.jq"
export NIXBOOK_SHELL_BUILTIN="$builtin"
export NIXBOOK_SHELL_LIVE_KEYS="$tmp/live-keys.json"
nix-instantiate --eval --strict --json \
  --expr "(import $root/lib.nix { lib = (import (import $root/npins).nixpkgs { }).lib; }).liveKeys" \
  >"$NIXBOOK_SHELL_LIVE_KEYS"
config_tool() { bash "$scripts/config-tool.sh" "$@"; }

if config_tool diff >/dev/null 2>&1; then
  fail "config-tool: diff without a live config.json fails"
else
  pass "config-tool: diff without a live config.json fails"
fi

# Live config = built-in defaults with: one menu change (not in Nix), one
# change also pinned in Nix, and one runtime-owned (liveKeys) change.
jq '.ai.includeSystemContext = (.ai.includeSystemContext | not)
  | .background.centeredWallpaper = (.background.centeredWallpaper | not)
  | .background.wallpaperPath = "/some/wallpaper.png"' "$builtin" >"$cfg/config.json"
jq -n --slurpfile b "$builtin" \
  '{background: {centeredWallpaper: ($b[0].background.centeredWallpaper | not)}}' >"$cfg/nix-pinned-values.json"

menu_value=$(jq '.ai.includeSystemContext' "$cfg/config.json")
diff_out=$(config_tool diff)
expect_contains "config-tool diff: reports the menu change as a Nix line" "$diff_out" \
  "ai.includeSystemContext = $menu_value;"
expect_eq "config-tool diff: skips settings pinned in Nix and runtime-owned keys" \
  "1" "$(grep -cv '^#' <<<"$diff_out")"
if nix_to_json <<<"{ $(grep -v '^#' <<<"$diff_out") }" >/dev/null 2>&1; then
  pass "config-tool diff: output is valid Nix"
else
  fail "config-tool diff: output is valid Nix" "$diff_out"
fi

expect_eq "config-tool pinned: lists the keys set in Nix" \
  "background.centeredWallpaper" "$(config_tool pinned)"

dump_json=$(config_tool dump --json)
expect_eq "config-tool dump --json: every live change except runtime-owned keys" \
  '["ai.includeSystemContext","background.centeredWallpaper"]' \
  "$(mergejq -c 'include "config-merge"; [leaves | join(".")] | sort' <<<"$dump_json")"
dump_nix=$(config_tool dump | grep -v '^#')
if back=$(nix_to_json <<<"$dump_nix" 2>"$tmp/err") && same_json "$dump_json" "$back"; then
  pass "config-tool dump: Nix output equals dump --json"
else
  fail "config-tool dump: Nix output equals dump --json" "$(cat "$tmp/err")"
fi

cp "$builtin" "$cfg/config.json"
expect_eq "config-tool diff: nothing to report on an untouched config" \
  "# no menu changes outside Nix" "$(config_tool diff)"

expect_contains "config-tool path: prints the config location" "$(config_tool path)" "$cfg/config.json"
if config_tool bogus >/dev/null 2>&1; then
  fail "config-tool: unknown command exits non-zero"
else
  pass "config-tool: unknown command exits non-zero"
fi

# -- assistant-facts.py --------------------------------------------------------

cat >"$tmp/info.json" <<'EOF'
{
  "host": "testhost",
  "user": "tester",
  "coreFacts": [
    {"en": "Apply with switch in profiles/testhost/tester/default.nix.", "fr": "fr", "de": "de", "vi": "vi"}
  ],
  "modules": {
    "all": ["niri", "core", "gitConfig", "sway", "zshConfig", "core"],
    "enabled": ["niri", "core", "gitConfig"]
  },
  "pinned": {"bar.bottom": true, "ai.model": "x"},
  "packages": ["git", "foo.desktop", "bar.sh", "ripgrep"],
  "settingPaths": ["b.x", "a.y", "a.y"],
  "nvim": {
    "leader": " ",
    "localLeader": null,
    "keymaps": [
      {"key": "<leader>ff", "mode": "n", "action": "<cmd>Telescope find_files<cr>", "lua": false, "desc": null, "scope": null},
      {"key": "<leader>ff", "mode": "n", "action": ":Overridden<CR>", "lua": false, "desc": null, "scope": null},
      {"key": "gd", "mode": "", "action": "vim.lsp.buf.definition()", "lua": true, "desc": null, "scope": "event:LspAttach"},
      {"key": "<C-a>", "mode": ["n", "x"], "action": "function() x() end", "lua": true, "desc": "Ask opencode…", "scope": null},
      {"key": "<leader>m", "mode": "n", "action": ":MarkdownPreview<cr>", "lua": false, "desc": null, "scope": "filetype:markdown"}
    ]
  }
}
EOF
cat >"$tmp/binds.kdl" <<'EOF'
binds {
    Mod+T { spawn "kitty"; }
    Mod+Space { spawn "nixbook-shell" "ipc" "call" "search" "toggle"; }
    Mod+Left { focus-column-left; }
    Mod+Shift+Ctrl+Down { move-column-to-workspace-down; }
    XF86AudioRaiseVolume allow-when-locked=true { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%+"; }
    XF86AudioLowerVolume allow-when-locked=true { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%-"; }
    Mod+Q { close-window; }
    Mod+F12 { some-future-action "arg"; }
}
EOF
if facts=$(python3 "$scripts/assistant-facts.py" "$tmp/info.json" "$tmp/binds.kdl" 2>"$tmp/err"); then
  pass "assistant-facts.py runs"
  check_facts() {
    if jq -e "$2" <<<"$facts" >/dev/null; then
      pass "assistant-facts.py: $1"
    else
      fail "assistant-facts.py: $1" "$(jq -c "$2" <<<"$facts")"
    fi
  }
  check_facts "every language has one sentence per fact" \
    '(.facts | length) as $n | $n == (.kinds | length) and ([.factsI18n[] | length] | all(. == $n)) and (.factsI18n | keys) == ["de","fr","vi"]'
  check_facts "one fact per keybind" '[.kinds[] | select(startswith("bind:"))] | length == 8'
  check_facts "host and user are carried over" '.host == "testhost" and .user == "tester"'
  check_facts "desktop entries and scripts are not listed as packages" '.packages == ["git","ripgrep"]'
  check_facts "core facts are carried over" '[.kinds[] | select(. == "core")] | length == 1'
  check_facts "modules are deduplicated and sorted" '.modules.all == ["core","gitConfig","niri","sway","zshConfig"] and .modules.enabled == ["core","gitConfig","niri"]'
  check_facts "setting paths are deduplicated and sorted" '.settingPaths == ["a.y","b.x"]'
  check_facts "pinned settings become facts" '[.kinds[] | select(. == "setting")] | length == 2'
  for want in \
    "Press Mod+T to open a terminal (kitty)." \
    "Press Mod+Space to open the app launcher" \
    "Press Mod+Left to focus the column on the left." \
    "Press XF86AudioRaiseVolume to turn the volume up." \
    "Press XF86AudioLowerVolume to turn the volume down." \
    "Press Mod+F12 to some future action arg." \
    "The package ripgrep is installed." \
    "profiles/testhost/tester/default.nix"; do
    expect_contains "assistant-facts.py: fact \"${want:0:48}\"" "$(jq -r '.facts[]' <<<"$facts")" "$want"
  done
  check_facts "one fact per Neovim keymap, a later one for the same key replacing the earlier" \
    '([.kinds[] | select(startswith("nvim:"))] | length) == 4 and (.nvim.keymaps | length) == 4'
  check_facts "the Neovim leader is named" '.nvim.leader == "Space" and .nvim.localLeader == "\\"'
  for want in \
    "In Neovim (normal mode), <leader>ff: run :Overridden." \
    "In Neovim (normal, visual, operator-pending mode, in buffers with an LSP server), gd: LSP: definition." \
    "In Neovim (normal, visual mode), <C-a>: Ask opencode." \
    "In Neovim (normal mode, in markdown files), <leader>m: run :MarkdownPreview." \
    "In Neovim, the leader key (<leader>) is Space."; do
    expect_contains "assistant-facts.py: fact \"${want:0:48}\"" "$(jq -r '.facts[]' <<<"$facts")" "$want"
  done
  md=$(python3 "$scripts/assistant-facts.py" --nvim-markdown "$tmp/info.json")
  expect_contains "assistant-facts.py --nvim-markdown lists the keymaps" "$md" '- `gd` (normal, visual, operator-pending mode, in buffers with an LSP server): LSP: definition'
  check_facts "the composed move action is described" \
    '[.facts[] | select(startswith("Press Mod+Shift+Ctrl+Down to move "))] | length == 1'
else
  fail "assistant-facts.py runs" "$(cat "$tmp/err")"
fi
if python3 "$scripts/assistant-facts.py" "$tmp/info.json" /dev/null >/dev/null 2>"$tmp/err"; then
  pass "assistant-facts.py: works without keybinds (niri disabled)"
else
  fail "assistant-facts.py: works without keybinds (niri disabled)" "$(cat "$tmp/err")"
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures nixbook-shell test(s) failed" >&2
  exit 1
fi
echo "all nixbook-shell tests passed"
