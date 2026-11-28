#!/usr/bin/env bash
# Try a darwin.nix machine's desktop (OmniWM, the keybindings, the tools) on a
# Mac that isn't yours: a rented one, or a VM on a Mac. `darwin-try` in the
# devenv shell. It installs Lix if needed, copies this checkout in (~/nixbook),
# builds the machine for that Mac's account (darwin.nix's withUser) and
# switches the Mac to it: only use it on a Mac you can throw away.
#
#   darwin-try remote USER@ADDRESS [HOST]   a Mac you reach by ssh (rented: e.g.
#                                           Scaleway's Apple silicon Mac minis;
#                                           its desktop then over VNC); again
#                                           after a change
#   darwin-try vm up [HOST]                 on an Apple Silicon Mac: a tart macOS
#                                           VM (first time: a ~25 GB image), in a
#                                           window, switched to HOST
#   darwin-try vm switch [HOST]             copy the checkout again and switch
#   darwin-try vm ssh [CMD...] | stop | delete
#
# HOST defaults to talia. Needs macOS 26+ on Apple Silicon there (OmniWM), an
# admin account (the switch runs sudo) and the network (Lix's installer,
# cache.nixos.org). macOS's licence allows macOS VMs on Apple hardware only.
#
# vm: Cirrus Labs' macOS 26 base image (user admin, password admin);
# NIXBOOK_DARWIN_VM (name), NIXBOOK_DARWIN_VM_IMAGE, NIXBOOK_DARWIN_VM_CPU,
# NIXBOOK_DARWIN_VM_MEMORY (MB), NIXBOOK_DARWIN_VM_DISK (GB).
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
vm=${NIXBOOK_DARWIN_VM:-nixbook-darwin}
image=${NIXBOOK_DARWIN_VM_IMAGE:-ghcr.io/cirruslabs/macos-tahoe-base:latest}
cpu=${NIXBOOK_DARWIN_VM_CPU:-4}
memory=${NIXBOOK_DARWIN_VM_MEMORY:-8192}
disk=${NIXBOOK_DARWIN_VM_DISK:-100}
vm_user="admin"
vm_password="admin"
state="${XDG_STATE_HOME:-$HOME/.local/state}/nixbook-darwin-try"
ssh_opts=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)

usage() {
  awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0" >&2
}

# run_on: the command the Mac runs things with (set per mode below).
run_on=()
on_mac() { "${run_on[@]}" "$@"; }

switch() {
  local host=$1
  if ! on_mac 'test -x /nix/var/nix/profiles/default/bin/nix'; then
    echo "== installing Lix"
    on_mac 'curl -sSf -L https://install.lix.systems/lix | sh -s -- install --no-confirm'
  fi

  echo "== copying $repo in (~/nixbook)"
  # .git comes along: getRevision.nix reads it. Build outputs and dev state don't.
  tar -C "$repo" -czf - \
    --exclude ./.devenv --exclude ./.direnv --exclude ./.tmp --exclude ./.gcroots \
    --exclude ./docs/node_modules --exclude './result*' . |
    on_mac 'rm -rf ~/nixbook.new && mkdir ~/nixbook.new && tar -xzf - -C ~/nixbook.new &&
            rm -rf ~/nixbook && mv ~/nixbook.new ~/nixbook'

  echo "== building $host for this account and switching"
  # As darwin-switch (not there yet the first time), after moving the files
  # the Nix installer wrote, which nix-darwin won't replace.
  on_mac "set -euo pipefail
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    cd ~/nixbook
    export NIXPKGS_ALLOW_UNFREE=1
    out=\$(nix-build --no-out-link --argstr host '$host' --argstr user \"\$(id -un)\" \\
      -E '{ host, user }: ((import ./darwin.nix).withUser host user).system')
    for f in /etc/nix/nix.conf /etc/bashrc /etc/zshrc /etc/zshenv; do
      if [ -e \"\$f\" ] && [ ! -L \"\$f\" ]; then sudo mv \"\$f\" \"\$f.before-nix-darwin\"; fi
    done
    sudo -H nix-env -p /nix/var/nix/profiles/system --set \"\$out\"
    sudo -H \"\$out/activate\"
    echo \"\$out\""

  cat <<EOF

== the Mac runs $host now. On its desktop, the first time:
  - System Settings → Privacy & Security → Accessibility and Input Monitoring: allow OmniWM
  - log out and back in (Apple menu): "Displays have separate Spaces" takes effect
Then Option+Return opens kitty, Option+Left/Right moves between columns,
Option+Tab is the overview (KEYBINDS.md, "OmniWM (macOS)").
After a change here, run the same darwin-try command again.
EOF
}

# -- tart VM ---------------------------------------------------------------------
vm_tools() {
  if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != arm64 ]; then
    echo "darwin-try vm: needs an Apple Silicon Mac (tart, Apple's Virtualization framework)." >&2
    echo "Without one: darwin-try remote USER@ADDRESS on a rented Mac." >&2
    exit 2
  fi
  # tart and sshpass from the pinned nixpkgs (lib/pkgs.nix allows tart's licence).
  local tools
  tools=$(nix-build --no-out-link -E "with import $repo/lib/pkgs.nix { }; buildEnv {
    name = \"darwin-try-tools\"; paths = [ tart sshpass jq ]; }")
  PATH="$tools/bin:$PATH"
  mkdir -p "$state"
}
vm_exists() { tart list --format json | jq -e --arg n "$vm" 'any(.[]; .Name == $n)' >/dev/null; }
vm_running() { tart list --format json | jq -e --arg n "$vm" 'any(.[]; .Name == $n and .State == "running")' >/dev/null; }
vm_connect() {
  local addr
  addr=$(tart ip "$vm" --wait 180)
  # A throwaway VM with a known password: no host key to keep.
  run_on=(sshpass -p "$vm_password" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
    -o LogLevel=ERROR -o ConnectTimeout=5 "$vm_user@$addr")
}
vm_start() {
  if ! vm_exists; then
    echo "== creating $vm from $image (the first time downloads it)"
    tart clone "$image" "$vm"
    tart set "$vm" --cpu "$cpu" --memory "$memory" --disk-size "$disk"
  fi
  if ! vm_running; then
    echo "== starting $vm (its window opens; log: $state/tart.log)"
    nohup tart run "$vm" >"$state/tart.log" 2>&1 &
  fi
  echo "== waiting for $vm"
  vm_connect
  local tries=0
  until on_mac true 2>/dev/null; do
    tries=$((tries + 1))
    [ "$tries" -lt 60 ] || {
      echo "darwin-try: no ssh into $vm after 5 minutes" >&2
      exit 1
    }
    sleep 5
  done
}

cmd=${1:-}
[ $# -gt 0 ] && shift
case "$cmd" in
remote)
  target=${1:?usage: darwin-try remote USER@ADDRESS [HOST]}
  run_on=(ssh "${ssh_opts[@]}" "$target")
  # shellcheck disable=SC2016 # expanded on the Mac
  on_mac 'test "$(uname -s)" = Darwin && test "$(uname -m)" = arm64' || {
    echo "darwin-try: $target isn't an Apple Silicon Mac" >&2
    exit 1
  }
  switch "${2:-talia}"
  ;;
vm)
  vm_tools
  sub=${1:-}
  [ $# -gt 0 ] && shift
  case "$sub" in
  up)
    vm_start
    switch "${1:-talia}"
    ;;
  switch)
    vm_running || {
      echo "darwin-try: $vm isn't running (darwin-try vm up)" >&2
      exit 1
    }
    vm_connect
    switch "${1:-talia}"
    ;;
  ssh)
    vm_connect
    on_mac "$@"
    ;;
  stop) tart stop "$vm" ;;
  delete)
    if vm_running; then tart stop "$vm"; fi
    tart delete "$vm"
    ;;
  *)
    usage
    exit 2
    ;;
  esac
  ;;
*)
  usage
  exit 2
  ;;
esac
