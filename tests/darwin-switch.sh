#!/usr/bin/env bash
# Builds a macOS machine (darwin.nix's `withUser HOST <the runner's user>`: the
# machine for that account) and activates it, as darwin-switch does on the Mac, then
# checks the result. For build.yaml's `build (<host>)` on a GitHub macOS runner
# (a throwaway VM: this changes the whole system); never run it on a real Mac.
#   tests/darwin-switch.sh talia
set -euo pipefail

host="${1:?usage: tests/darwin-switch.sh HOST}"
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"
export NIXPKGS_ALLOW_UNFREE=1

if [ "$(uname -s)" != Darwin ] || [ "${CI:-}" != true ]; then
  echo "tests/darwin-switch.sh: only for a macOS CI runner (it replaces the system)" >&2
  exit 2
fi

user=$(id -un)
home=$HOME

echo "== build $host for $user"
out=$(nix-build --no-out-link --show-trace --argstr host "$host" --argstr user "$user" \
  -E '{ host, user }: ((import ./darwin.nix).withUser host user).system')
echo "$out"

echo "== activate"
# The Nix installer wrote these; nix-darwin refuses to replace a file it
# doesn't own, and takes the *.before-nix-darwin copy as the sign it may.
for f in /etc/nix/nix.conf /etc/bashrc /etc/zshrc /etc/zshenv; do
  if [ -e "$f" ] && [ ! -L "$f" ]; then
    sudo mv "$f" "$f.before-nix-darwin"
  fi
done
sudo -H nix-env -p /nix/var/nix/profiles/system --set "$out"
sudo -H "$out/activate"

echo "== checks"
failed=0
# expect WHAT COMMAND...: ok when COMMAND succeeds.
expect() {
  local what=$1
  shift
  if "$@"; then
    echo "ok   - $what"
  else
    echo "FAIL - $what" >&2
    failed=1
  fi
}
# shellcheck disable=SC2329 # called through expect
is_current() { [ "$(readlink /run/current-system)" = "$out" ]; }
# shellcheck disable=SC2329
has_rev() { jq -e '.rev | length > 0' /etc/nixos/version >/dev/null; }
# shellcheck disable=SC2329
separate_spaces() { [ "$(defaults read com.apple.spaces spans-displays 2>/dev/null)" = 0 ]; }

expect "/run/current-system is the new system" is_current
expect "darwin-switch installed" test -x /run/current-system/sw/bin/darwin-switch
# Not run: it applies main from GitHub, not this change.
expect "osupdate installed" test -x /run/current-system/sw/bin/osupdate
expect "ginx installed" test -x /run/current-system/sw/bin/ginx
expect "/etc/nixos/version has the revision" has_rev
expect "nix.conf is nixbook's" grep -q didactiklabs-nixcache /etc/nix/nix.conf
expect "Displays have separate Spaces (OmniWM)" separate_spaces
expect "Touch ID for sudo" grep -q pam_tid /etc/pam.d/sudo_local

# Home Manager, activated for the runner's user.
for agent in org.nix-community.home.omniwm org.nix-community.home.omniwm-nix-settings; do
  expect "launchd agent $agent" test -f "$home/Library/LaunchAgents/$agent.plist"
done
hm_path="/etc/profiles/per-user/$user/bin"
for bin in OmniWM omniwmctl nvim kitty kubectl starship zsh; do
  expect "$bin in the user profile" test -x "$hm_path/$bin"
done
expect "the user's zsh starts" "$hm_path/zsh" -i -c 'exit 0'

# Apps copied where Spotlight finds them (copyApps), Zen known to
# LaunchServices as a browser (making it the default needs a click in
# macOS's dialog: not checked).
apps="$home/Applications/Home Manager Apps"
# shellcheck disable=SC2329
has_app() { compgen -G "$apps/$1*.app" >/dev/null; }
for app in Zen Vesktop kitty; do
  expect "$app copied into $apps" has_app "$app"
done
# shellcheck disable=SC2329
zen_is_browser() { nix-shell -p defaultbrowser --run defaultbrowser | grep -qiE 'zen|twilight'; }
expect "Zen is a registered browser" zen_is_browser

# darwin-switch, with no option, builds the same system (this host, this user).
again=$(/run/current-system/sw/bin/darwin-switch --build --repo "$repo" 2>/dev/null | tail -n 1)
expect "darwin-switch --build gives the same system ($again)" test "$again" = "$out"

exit "$failed"
