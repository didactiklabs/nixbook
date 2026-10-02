#!/usr/bin/env bash
# Tests for the nixbook-shell helper scripts (scripts/):
#   - config-merge.jq: the JSON -> Nix printers must round-trip through Nix;
#   - config-tool.sh: `nixbook-shell config diff|pinned|dump|path` on fixtures;
#   - assistant-facts.py: fact file structure, keybind, Neovim keymap, system and how-to facts;
#   - theme-palettes.py + greeter-theme.sh: what the login screen gets;
#   - render-app-colors.py, zen-theme.py, apply-app-colors.sh: the app colours;
#   - applycolor.sh: the terminal colours (kitty's theme, escape sequences);
#   - least_busy_region.py: background widget placement and its cache.
# Needs bash, jq, python3, nix-instantiate and nix-build (the shell's Python
# environment, with OpenCV). Run: bash tests/scripts.sh
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
  "os": {
    "nixos": true, "release": "26.05", "codeName": "Yarara", "platform": "x86_64-linux", "kernel": "6.18.1",
    "host": "testhost", "user": "tester", "timeZone": null, "autoTimeZone": false, "locale": "fr_FR.UTF-8",
    "keyboard": {"layout": "fr", "variant": "azerty"}, "bootloader": "systemd-boot", "shell": "zsh",
    "editor": "nvim", "nix": "lix 2.95.2", "flakes": true, "users": ["tester", "guest"],
    "toggles": [
      {"path": "hardware.bluetooth", "scope": "nixos", "enabled": true, "description": "support for Bluetooth"},
      {"path": "services.openssh", "scope": "nixos", "enabled": false, "description": "the OpenSSH secure shell daemon"},
      {"path": "xdg.portal", "scope": "nixos", "enabled": true, "description": "[xdg desktop integration](https://example.org)"}
    ]
  },
  "howTo": {
    "apply": {"en": "Apply with deploy-tool.", "fr": "fr", "de": "de", "vi": "vi"}
  },
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
  md=$(python3 "$scripts/assistant-facts.py" --markdown "$tmp/info.json")
  expect_contains "assistant-facts.py --markdown lists the keymaps" "$md" '- `gd` (normal, visual, operator-pending mode, in buffers with an LSP server): LSP: definition'
  check_facts "the operating system becomes facts" '[.kinds[] | select(. == "os")] | length == 12'
  check_facts "only enabled toggles become facts, every toggle is listed" \
    '([.kinds[] | select(startswith("toggle:"))] | length) == 2 and (.toggles | length) == 3 and (.toggles | map(.enabled)) == [true,false,true]'
  check_facts "how-to answers become facts" '.kinds | index("howto:apply") != null'
  for want in \
    "This machine runs NixOS version 26.05" \
    "Yarara" \
    "The Linux kernel is version 6.18.1." \
    "The keyboard layout is fr (azerty)." \
    "Nix flakes are enabled." \
    "The user accounts on this machine are: tester, guest." \
    "bluetooth – support for Bluetooth is enabled (NixOS option hardware.bluetooth.enable)." \
    "portal – xdg desktop integration is enabled (NixOS option xdg.portal.enable)." \
    "Apply with deploy-tool."; do
    expect_contains "assistant-facts.py: fact \"${want:0:48}\"" "$(jq -r '.facts[]' <<<"$facts")" "$want"
  done
  expect_contains "assistant-facts.py --markdown lists the system" "$md" "- The Linux kernel is version 6.18.1."
  expect_contains "assistant-facts.py --markdown lists the how-tos" "$md" "- Apply with deploy-tool."
  expect_contains "assistant-facts.py --markdown lists the enabled toggles" "$md" "hardware.bluetooth, xdg.portal"
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

# -- theme-palettes.py + greeter-theme.sh: the login screen theme -------------

if python3 "$scripts/theme-palettes.py" "$root/src/modules/common/themes.json" >"$tmp/palettes.json" 2>"$tmp/err"; then
  pass "theme-palettes.py reads themes.json"
  expect_eq "theme-palettes.py: every Persona variant, in order" '["p5","p3r","p4"]' "$(jq -c '.themes.persona.variants' "$tmp/palettes.json")"
  expect_eq "theme-palettes.py: the p5 accent" '#ff1f2d' "$(jq -r '.themes.persona.palettes.p5.primary' "$tmp/palettes.json")"
  expect_eq "theme-palettes.py: the default theme" 'material' "$(jq -r '.default' "$tmp/palettes.json")"
  expect_eq "theme-palettes.py: a theme's defaultVariant" 'chiikawa' "$(jq -r '.themes.chiikawa.default' "$tmp/palettes.json")"
  expect_eq "theme-palettes.py: the Cyberpunk variants, yellow first" '["yellow","red"]' "$(jq -c '.themes.cyberpunk.variants' "$tmp/palettes.json")"
else
  fail "theme-palettes.py reads themes.json" "$(cat "$tmp/err")"
fi
# A malformed registry fails (the login screen build with it).
bad_registry() {
  printf '%s\n' "$2" >"$tmp/bad-themes.json"
  if python3 "$scripts/theme-palettes.py" "$tmp/bad-themes.json" >/dev/null 2>&1; then
    fail "theme-palettes.py rejects $1"
  else
    pass "theme-palettes.py rejects $1"
  fi
}
bad_registry "an unknown default" '{"default":"nope","themes":[{"id":"a","name":"A","icon":"x","variants":[]}]}'
bad_registry "a duplicate theme" '{"default":"a","themes":[{"id":"a","name":"A","icon":"x","variants":[]},{"id":"a","name":"A","icon":"x","variants":[]}]}'
bad_registry "an id that isn't a settings key" '{"default":"a.b","themes":[{"id":"a.b","name":"A","icon":"x","variants":[]}]}'
bad_registry "an incomplete palette" '{"default":"a","themes":[{"id":"a","name":"A","icon":"x","variants":[{"id":"v","name":"V","icon":"x","palette":{"background":"#000000"}}]}]}'

# greeter_theme NAME CONFIG_JSON [COLORS_JSON]: exports into $tmp/greeter/NAME.
greeter_theme() {
  local out="$tmp/greeter/$1" in="$tmp/greeter-in/$1"
  mkdir -p "$out" "$in"
  printf '%s\n' "$2" >"$in/config.json"
  rm -f "$in/colors.json"
  [ $# -lt 3 ] || printf '%s\n' "$3" >"$in/colors.json"
  NB_OUT="$out" NB_PALETTES="$tmp/palettes.json" \
    NB_CONFIG="$in/config.json" NB_COLORS="$in/colors.json" NB_COPY_BACKGROUND=1 \
    bash "$scripts/greeter-theme.sh" 2>"$tmp/err" || fail "greeter-theme.sh: $1 exports" "$(cat "$tmp/err")"
}
bg() { cat "$tmp/greeter/$1/bg"; }

# The first frame's colour: the theme's palette, else the wallpaper's.
greeter_theme p3r '{"appearance":{"theme":"persona","persona":{"variant":"p3r"}}}'
expect_eq "greeter-theme.sh: a Persona variant's background" "#050f26" "$(bg p3r)"
greeter_theme usagi '{"appearance":{"theme":"chiikawa","chiikawa":{"variant":"usagi"}}}'
expect_eq "greeter-theme.sh: a Chiikawa variant's background" "#fffbeb" "$(bg usagi)"
greeter_theme chiikawa '{"appearance":{"theme":"chiikawa"}}' '{"background":"#123456"}'
expect_eq "greeter-theme.sh: a theme's default variant" "#fffaf6" "$(bg chiikawa)"
greeter_theme cyberpunk-red '{"appearance":{"theme":"cyberpunk","cyberpunk":{"variant":"red"}}}'
expect_eq "greeter-theme.sh: a Cyberpunk variant's background" "#0a0506" "$(bg cyberpunk-red)"
greeter_theme material '{"appearance":{"theme":"material"}}' '{"background":"#123456","primary":"#abcdef"}'
expect_eq "greeter-theme.sh: Material: the wallpaper palette" "#123456" "$(bg material)"
greeter_theme persona-wallpaper '{"appearance":{"theme":"persona","persona":{"palette":false}}}' '{"background":"#123456"}'
expect_eq "greeter-theme.sh: palette false keeps the wallpaper's under the theme" "#123456" "$(bg persona-wallpaper)"
greeter_theme legacy '{"appearance":{"persona":{"enable":true,"variant":"p3r"}}}'
expect_eq "greeter-theme.sh: legacy persona.enable still means Persona" "#050f26" "$(bg legacy)"
greeter_theme unknown '{"appearance":{"theme":"nope"}}'
expect_eq "greeter-theme.sh: an unknown theme falls back to the default" "#141313" "$(bg unknown)"
greeter_theme bad-variant '{"appearance":{"theme":"persona","persona":{"variant":"p9"}}}'
expect_eq "greeter-theme.sh: an unknown variant falls back to the first" "#0a0a0a" "$(bg bad-variant)"

# What the greeter is given: the look only.
greeter_theme exported '{"appearance":{"theme":"chiikawa","themeWallpapers":["x=/y"]},"time":{"format":"HH:mm"},"ai":{"systemPrompt":"secret"},"apps":{"terminal":"rm -rf"},"lock":{"materialShapeChars":true,"x":1}}' '{"primary":"#abcdef","secondary":"red; } *"}'
settings=$(cat "$tmp/greeter/exported/settings.json")
expect_eq "greeter-theme.sh: the theme, for the greeter" chiikawa "$(jq -r .appearance.theme <<<"$settings")"
expect_eq "greeter-theme.sh: the time format" HH:mm "$(jq -r .time.format <<<"$settings")"
expect_eq "greeter-theme.sh: nothing but the look (no ai, apps, per-variant paths)" '["appearance","language","lock","time"]' "$(jq -c 'keys' <<<"$settings")"
expect_eq "greeter-theme.sh: ...no wallpaper lists" null "$(jq -c .appearance.themeWallpapers <<<"$settings")"
expect_eq "greeter-theme.sh: ...only the lock's password dots" '{"materialShapeChars":true}' "$(jq -c .lock <<<"$settings")"
expect_eq "greeter-theme.sh: the palette, invalid colours dropped" '{"primary":"#abcdef"}' "$(cat "$tmp/greeter/exported/colors.json")"

# The account picture: copied when it is an image.
printf 'png' >"$tmp/face.png"
greeter_theme avatar "{\"profile\":{\"avatarPath\":\"file://$tmp/face.png\"}}"
expect_eq "greeter-theme.sh: the account picture" png "$(cat "$tmp/greeter/avatar/avatar")"
greeter_theme avatar '{"profile":{"avatarPath":"/etc/shadow"}}'
if [ -e "$tmp/greeter/avatar/avatar" ]; then fail "greeter-theme.sh: only images as the account picture"; else pass "greeter-theme.sh: only images as the account picture"; fi

# Login screen wallpaper: greeterWall, then lockWall, then the desktop's.
printf 'desk' >"$tmp/desk.png"
printf 'lock' >"$tmp/lock.png"
printf 'greet' >"$tmp/greet.png"
greeter_theme walls "{\"background\":{\"wallpaperPath\":\"$tmp/desk.png\",\"lockWall\":\"$tmp/lock.png\",\"greeterWall\":\"$tmp/greet.png\"}}"
expect_eq "greeter-theme.sh: the login screen wallpaper first" greet "$(cat "$tmp/greeter/walls/background")"
greeter_theme walls "{\"background\":{\"wallpaperPath\":\"$tmp/desk.png\",\"lockWall\":\"$tmp/lock.png\",\"greeterWall\":\"\"}}"
expect_eq "greeter-theme.sh: else the lock screen's" lock "$(cat "$tmp/greeter/walls/background")"
greeter_theme walls "{\"background\":{\"wallpaperPath\":\"file://$tmp/desk.png\",\"lockWall\":\"$tmp/missing.png\"}}"
expect_eq "greeter-theme.sh: else the desktop's (file:// and missing files handled)" desk "$(cat "$tmp/greeter/walls/background")"
greeter_theme walls '{}'
if [ -e "$tmp/greeter/walls/background" ]; then fail "greeter-theme.sh: no wallpaper, none copied"; else pass "greeter-theme.sh: no wallpaper, none copied"; fi

# -- App colours: render-app-colors.py, zen-theme.py, apply-app-colors.sh ------

colors="$root/src/scripts/colors"
palette='{"primary":"#AbCdEf","surface":"#ff112233","not_a_colour":"blue"}'
printf 'p={{colors.primary.default.hex}} r={{colors.primary.default.red}} s={{ colors.surface.default.hex }}\n' >"$tmp/app.tpl"
out=$("$colors/render-app-colors.py" "$tmp/app.tpl" "$tmp/apps/a.txt" <<<"$palette")
expect_eq "render-app-colors.py: placeholders filled (alpha dropped, lower case)" "p=#abcdef r=171 s=#112233" "$(cat "$tmp/apps/a.txt")"
expect_eq "render-app-colors.py: prints what changed" "$tmp/apps/a.txt" "$out"
out=$("$colors/render-app-colors.py" "$tmp/app.tpl" "$tmp/apps/a.txt" <<<"$palette")
expect_eq "render-app-colors.py: ...and nothing when unchanged" "" "$out"
printf '{{colors.tertiary.default.hex}}\n' >"$tmp/missing.tpl"
if "$colors/render-app-colors.py" "$tmp/missing.tpl" "$tmp/apps/m.txt" <<<"$palette" 2>/dev/null || [ -e "$tmp/apps/m.txt" ]; then
  fail "render-app-colors.py: a colour missing fails, nothing written"
else
  pass "render-app-colors.py: a colour missing fails, nothing written"
fi
# A light theme palette with a pastel primary (Chiikawa's Momonga): the
# primary is darkened until it reads as text on the surface (4.5:1), its
# on_primary follows, readable colours stay as they are.
light='{"surface":"#fcf9ff","on_surface":"#2d2540","primary":"#b7a4e9","on_primary":"#1f1438"}'
printf '{{colors.primary.default.hex}} {{colors.on_primary.default.hex}} {{colors.on_surface.default.hex}} {{mode}}\n' >"$tmp/modes.tpl"
"$colors/render-app-colors.py" "$tmp/modes.tpl" "$tmp/apps/light.txt" <<<"$light" >/dev/null
expect_eq "render-app-colors.py: text roles made readable" "#7d5ad7 #f9f7fc #2d2540 light" "$(cat "$tmp/apps/light.txt")"
dark='{"surface":"#141218","on_surface":"#e6e0e9","primary":"#d0bcff","on_primary":"#381e72"}'
"$colors/render-app-colors.py" "$tmp/modes.tpl" "$tmp/apps/dark.txt" <<<"$dark" >/dev/null
expect_eq "render-app-colors.py: a readable dark palette is left alone" "#d0bcff #381e72 #e6e0e9 dark" "$(cat "$tmp/apps/dark.txt")"

# A home with a Zen profile (relative path in profiles.ini) and Vesktop
# settings.
home="$tmp/home"
zen_profile="$home/.config/zen/abc.default"
mkdir -p "$zen_profile" "$home/.config/vesktop/settings"
printf '[General]\nStartWithLastProfile=1\n\n[Profile0]\nName=default\nIsRelative=1\nPath=abc.default\n' >"$home/.config/zen/profiles.ini"
printf 'body { color: red; }\n' >"$tmp/userChrome.css"
cp "$tmp/userChrome.css" "$zen_profile/chrome.keep" && mkdir -p "$zen_profile/chrome" && mv "$zen_profile/chrome.keep" "$zen_profile/chrome/userChrome.css"
printf 'user_pref("browser.startup.page", 3);\n' >"$zen_profile/prefs.js"
echo '{"enabledThemes":["other.css"]}' >"$home/.config/vesktop/settings/settings.json"
in_home() { HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_STATE_HOME="$home/.local/state" XDG_DATA_HOME="$home/.local/share" XDG_RUNTIME_DIR="$tmp" "$@"; }

expect_eq "zen-theme.py: profiles from profiles.ini" "$(realpath "$zen_profile")" "$(in_home "$colors/zen-theme.py" profiles)"

# Every role the templates use, all #abcdef.
full_palette=$(grep -ohE 'colors\.[a-z_]+\.default' "$colors"/app-templates/* | cut -d. -f2 | sort -u |
  jq -R -s -c 'split("\n") | map(select(. != "")) | map({(.): "#abcdef"}) | add')
in_home "$colors/apply-app-colors.sh" "$full_palette" vesktop,zen
expect_eq "apply-app-colors.sh: Vesktop theme written" "true" "$(grep -q '#abcdef' "$home/.config/vesktop/themes/nixbook-shell.css" && echo true)"
expect_eq "apply-app-colors.sh: ...and turned on, other themes kept" '["other.css","nixbook-shell.css"]' "$(jq -c .enabledThemes "$home/.config/vesktop/settings/settings.json")"
expect_eq "apply-app-colors.sh: Zen CSS in the profile" "true" "$(grep -q '#abcdef' "$zen_profile/chrome/nixbook-shell.css" && echo true)"
expect_eq "zen-theme.py: import first, the rest of userChrome.css kept" '@import url("nixbook-shell.css");'$'\n''body { color: red; }' "$(cat "$zen_profile/chrome/userChrome.css")"
expect_contains "zen-theme.py: userChrome pref set while Zen is closed" "$(cat "$zen_profile/prefs.js")" 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);'
expect_contains "zen-theme.py: ...other prefs kept" "$(cat "$zen_profile/prefs.js")" 'user_pref("browser.startup.page", 3);'
in_home "$colors/zen-theme.py" sync
expect_eq "zen-theme.py: sync is idempotent" 1 "$(grep -c '@import' "$zen_profile/chrome/userChrome.css")"

# Running (its lock points at a live pid): prefs.js untouched, a restart
# needed only when its CSS changed.
ln -s "127.0.0.1:+$$" "$zen_profile/lock"
status=0
in_home "$colors/zen-theme.py" sync || status=$?
expect_eq "zen-theme.py: running, CSS unchanged: no restart" 0 "$status"
status=0
in_home "$colors/zen-theme.py" sync "$zen_profile/chrome/nixbook-shell.css" || status=$?
expect_eq "zen-theme.py: running, CSS changed: restart (exit 3)" 3 "$status"
rm "$zen_profile/lock"

in_home "$colors/apply-app-colors.sh" "$full_palette" ""
expect_eq "apply-app-colors.sh: switched off, Vesktop theme turned off" '["other.css"]' "$(jq -c .enabledThemes "$home/.config/vesktop/settings/settings.json")"
expect_eq "apply-app-colors.sh: ...Zen import removed" 'body { color: red; }' "$(cat "$zen_profile/chrome/userChrome.css")"
if [ -e "$zen_profile/chrome/nixbook-shell.css" ] || [ -e "$home/.config/vesktop/themes/nixbook-shell.css" ]; then
  fail "apply-app-colors.sh: ...generated files removed"
else
  pass "apply-app-colors.sh: ...generated files removed"
fi

# -- least_busy_region.py: background widget placement -------------------------

# The shell's own Python environment (OpenCV, numpy), as packaged.
lbr_python="$(nix-build --no-out-link -E "(import $root { }).package.passthru.shell.passthru.pythonEnv")/bin/python3"
lbr_dir="$root/src/scripts/images"
lbr() { PYTHONDONTWRITEBYTECODE=1 XDG_CACHE_HOME="$tmp/lbr-cache" "$lbr_python" "$lbr_dir/least_busy_region.py" "$@"; }

# The window scans give what a plain scan of every window gives (ties
# included: the first one in row order wins).
if out=$(
  PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$lbr_dir" "$lbr_python" - 2>&1 <<'EOF'
import numpy as np
import least_busy_region as L
L.load_cv()

def variance(img, x, y, w, h):
    win = img[y:y + h, x:x + w].astype(np.float64)
    return (win ** 2).sum() / (w * h) - (win.sum() / (w * h)) ** 2

def least_busy(img, rw, rh, stride, hp, vp, busiest):
    h, w = img.shape
    rw, rh = min(rw, w - 2 * hp), min(rh, h - 2 * vp)
    best = None
    for y in range(vp, max(vp, h - rh - vp + 1) + 1, stride):
        for x in range(hp, max(hp, w - rw - hp + 1) + 1, stride):
            if x + rw > w or y + rh > h:
                continue
            v = variance(img, x, y, rw, rh)
            if best is None or (v > best[1] if busiest else v < best[1]):
                best = ((x, y), v)
    return best

def largest(img, stride, thr, ar, hp, vp):
    h, w = img.shape
    ew, eh = w - 2 * hp, h - 2 * vp
    lo, hi = 10, (min(eh, int(ew / ar)) if ar >= 1 else min(int(eh * ar), ew))
    best = None
    while lo <= hi:
        mid = (lo + hi) // 2
        rw, rh = (int(round(mid * ar)), mid) if ar >= 1 else (mid, int(round(mid / ar)))
        if rw > ew or rh > eh:
            hi = mid - 1
            continue
        hit = next(((x, y) for y in range(vp, h - rh - vp + 1, stride)
                    for x in range(hp, w - rw - hp + 1, stride)
                    if variance(img, x, y, rw, rh) <= thr), None)
        if hit:
            best = ((hit[0] + rw // 2, hit[1] + rh // 2), (rw, rh))
            lo = mid + 1
        else:
            hi = mid - 1
    return best

rng = np.random.default_rng(7)
noise = rng.integers(0, 256, (90, 140), dtype=np.uint8)
patchy = noise.copy()
patchy[:, :70] = 40  # a flat half: many equal windows
images = [noise, patchy, np.full((60, 80), 128, np.uint8)]
bad = []
for i, img in enumerate(images):
    for rw, rh in [(20, 12), (33, 30), (500, 500)]:
        for stride in [1, 4, 10]:
            for hp, vp in [(0, 0), (3, 5)]:
                for busiest in (False, True):
                    want = least_busy(img, rw, rh, stride, hp, vp, busiest)
                    got = L.find_least_busy_region(img, rw, rh, stride=stride, horizontal_padding=hp,
                                                   vertical_padding=vp, busiest=busiest)
                    if want[0] != got[0] or not np.isclose(want[1], got[1], atol=1e-6):
                        bad.append(("least busy", i, rw, rh, stride, hp, vp, busiest, want, got))
    for stride in [1, 5]:
        for thr in [0.0, 300.0, 1e9]:
            for ar in [1.78, 0.6]:
                want = largest(img, stride, thr, ar, 2, 2)
                got = L.find_largest_region(img, stride=stride, threshold=thr, aspect_ratio=ar,
                                            horizontal_padding=2, vertical_padding=2)
                if want != (got[:2] if got[0] else None):
                    bad.append(("largest", i, stride, thr, ar, want, got))
print("\n".join(map(str, bad[:5])) if bad else "same")
EOF
) && [ "$out" = same ]; then
  pass "least_busy_region.py: window scans match a plain scan"
else
  fail "least_busy_region.py: window scans match a plain scan" "$out"
fi

# A noisy wallpaper with one flat block: the widget goes on the block.
lbr_wall="$tmp/lbr-wall.png"
PYTHONDONTWRITEBYTECODE=1 "$lbr_python" -c '
import sys, cv2, numpy as np
img = np.random.default_rng(3).integers(0, 256, (540, 960, 3), dtype=np.uint8)
img[300:500, 600:900] = (40, 90, 200)  # BGR
cv2.imwrite(sys.argv[1], img)' "$lbr_wall"
lbr_args=(--screen-width 960 --screen-height 540 --width 200 --height 150 --horizontal-padding 20 --vertical-padding 20)
cold=$(lbr "${lbr_args[@]}" "$lbr_wall")
expect_eq "least_busy_region.py: widget placed on the flat block" '[true,true,"#c85a28"]' \
  "$(jq -c '[(.center_x >= 700 and .center_x <= 800), (.center_y >= 375 and .center_y <= 425), .dominant_color]' <<<"$cold")"
expect_eq "least_busy_region.py: --busiest avoids it" 'true' \
  "$(lbr "${lbr_args[@]}" --busiest "$lbr_wall" | jq '.center_x < 600 or .center_y < 300')"

# The cache: private, the same answer, a new one when the wallpaper changes.
lbr_cache="$tmp/lbr-cache/nixbook-shell/least-busy-region"
expect_eq "least_busy_region.py: cache directories are private" '700 700 700' \
  "$(stat -c %a "$lbr_cache" "$lbr_cache/results" "$lbr_cache/images" | tr '\n' ' ' | sed 's/ $//')"
expect_eq "least_busy_region.py: cached answer is the same" "$cold" "$(lbr "${lbr_args[@]}" "$lbr_wall")"
expect_eq "least_busy_region.py: one answer per argument set" 2 "$(find "$lbr_cache/results" -name '*.json' | wc -l)"
expect_eq "least_busy_region.py: one decoded image per wallpaper and screen" 1 "$(find "$lbr_cache/images" -name '*.npy' | wc -l)"
for f in "$lbr_cache"/results/*.json; do printf 'not json' >"$f"; done
expect_eq "least_busy_region.py: a broken cache entry is recomputed" "$cold" "$(lbr "${lbr_args[@]}" "$lbr_wall")"
PYTHONDONTWRITEBYTECODE=1 "$lbr_python" -c '
import sys, cv2, numpy as np
img = np.random.default_rng(4).integers(0, 256, (540, 960, 3), dtype=np.uint8)
img[40:200, 60:300] = 255
cv2.imwrite(sys.argv[1], img)' "$lbr_wall"
expect_eq "least_busy_region.py: a changed wallpaper is not served from the cache" '[true,"#ffffff"]' \
  "$(lbr "${lbr_args[@]}" "$lbr_wall" | jq -c '[.center_x < 400 and .center_y < 300, .dominant_color]')"
rm -rf "$tmp/lbr-cache"
lbr --no-cache "${lbr_args[@]}" "$lbr_wall" >/dev/null
expect_eq "least_busy_region.py: --no-cache writes nothing" 'absent' "$([ -e "$tmp/lbr-cache" ] && echo present || echo absent)"
mkdir -p "$tmp/lbr-cache" && chmod 500 "$tmp/lbr-cache"
expect_eq "least_busy_region.py: works without a writable cache" '"#ffffff"' \
  "$(lbr "${lbr_args[@]}" "$lbr_wall" | jq .dominant_color)"
chmod 700 "$tmp/lbr-cache"
if lbr "$tmp/missing.png" >/dev/null 2>"$tmp/err"; then
  fail "least_busy_region.py: a missing wallpaper is an error"
else
  expect_contains "least_busy_region.py: a missing wallpaper is an error" "$(cat "$tmp/err")" "Image not found"
fi

# -- applycolor.sh: terminal colours ---------------------------------------------
# A generated palette into kitty's theme and the escape sequences written to
# the open terminals (fake ones: NIXBOOK_SHELL_PTS_DIR), then turned off.
ac_home="$tmp/applycolor"
mkdir -p "$ac_home/state/quickshell/user/generated" "$ac_home/config/quickshell/nixbook-shell" \
  "$ac_home/config/nixbook-shell" "$ac_home/pts"
# Every colour the templates use: term0-15 distinct, the rest grey but for
# the selection's.
{
  for i in $(seq 0 15); do printf '$term%d: #%02x%02x%02x;\n' "$i" "$i" "$((i + 16))" "$((i + 32))"; done
  printf '$onSecondaryContainer: #aabbcc;\n$secondaryContainer: #223344;\n'
  grep -ohE '\$[a-zA-Z0-9]+ #' "$root/src/scripts/colors/terminal/"{kitty-theme.conf,sequences.txt} | sort -u |
    grep -vE '^\$(term[0-9]+|onSecondaryContainer|secondaryContainer) ' | sed 's/ #$/: #808080;/'
} >"$ac_home/state/quickshell/user/generated/material_colors.scss"
echo '{"appearance":{"wallpaperTheming":{"enableTerminal":true}}}' >"$ac_home/config/nixbook-shell/config.json"
: >"$ac_home/pts/3"
: >"$ac_home/pts/ptmx"
applycolor() {
  XDG_STATE_HOME="$ac_home/state" XDG_CONFIG_HOME="$ac_home/config" NIXBOOK_SHELL_PTS_DIR="$ac_home/pts" \
    bash "$root/src/scripts/colors/applycolor.sh" "$@" >/dev/null 2>&1
}
# Its writes run in the background: wait for them.
wait_for() { for _ in $(seq 50); do
  [ -s "$1" ] && return 0
  sleep 0.1
done; }
applycolor
wait_for "$ac_home/pts/3"
seqs=$(cat -v "$ac_home/pts/3")
expect_contains "applycolor.sh: the palette to the open terminals" "$seqs" '^[]4;1;#011121^['
expect_contains "applycolor.sh: the background, a plain colour" "$seqs" '^[]11;#001020^['
expect_contains "applycolor.sh: the selection colours" "$seqs" '^[]17;#aabbcc^['
expect_eq "applycolor.sh: no placeholder or alpha prefix left" "" "$(grep -oE '\$[a-zA-Z]|\[[0-9]+\]' <<<"$seqs" || true)"
expect_eq "applycolor.sh: not to ptmx" "" "$(cat "$ac_home/pts/ptmx")"
kitty_theme="$ac_home/state/quickshell/user/generated/terminal/kitty-theme.conf"
expect_contains "applycolor.sh: kitty's theme" "$(cat "$kitty_theme")" "color1                #011121"
expect_eq "applycolor.sh: kitty's theme fully filled in, no inline comment" "" \
  "$(grep -E '\$[a-zA-Z]|^[a-z_0-9]+ +#[0-9a-f]+ .' "$kitty_theme" || true)"
: >"$ac_home/pts/3"
applycolor --reset-terminal
wait_for "$ac_home/pts/3"
expect_contains "applycolor.sh --reset-terminal: the terminals' own colours back" "$(cat -v "$ac_home/pts/3")" '^[]104^['
expect_eq "applycolor.sh --reset-terminal: the generated theme gone (kitty, new shells)" "" \
  "$(ls "$ac_home/state/quickshell/user/generated/terminal")"

if [ "$failures" -ne 0 ]; then
  echo "$failures nixbook-shell test(s) failed" >&2
  exit 1
fi
echo "all nixbook-shell tests passed"
