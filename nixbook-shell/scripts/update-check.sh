#!/usr/bin/env bash
# nixbook-update-check REPO_URL: is there a newer revision of the system's
# repository, and what changed? The updates widget (services/UpdateState.qml)
# runs it through systemd-run, outside the shell: a dead network or a
# multi-megabyte GitHub /compare answer never blocks the shell. The answer
# goes to $XDG_STATE_HOME/nixbook-shell/update-check.json, which the bar reads:
#   {checking, time, error, localRev, localBranch, localDirty, remoteRev,
#    available, changelog: [commit titles, oldest first],
#    ci: "passed" | "pending" | "failed" | "" (main's build of remoteRev)}
# error: "" or no-repo, no-version, bad-version, timeout, unreachable.
set -uo pipefail

repo=${1:-}
version_file=${NIXBOOK_VERSION_FILE:-/etc/nixos/version}
dir="${XDG_STATE_HOME:-$HOME/.local/state}/nixbook-shell"
out="$dir/update-check.json"
mkdir -p "$dir"

write() {
  printf '%s\n' "$1" >"$out.tmp" && mv -f "$out.tmp" "$out"
}

# The last answer stays shown while checking.
prev=$(jq -c 'if type == "object" then . else {} end' "$out" 2>/dev/null) || prev='{}'
[ -n "$prev" ] || prev='{}'
done=0
finish() { # ERROR [RESULT]
  done=1
  write "$(jq -c --arg e "$1" --arg t "$(date +%H:%M)" '. + {checking: false, error: $e, time: $t}' <<<"${2:-$prev}")"
  exit 0
}
# Stopped (RuntimeMaxSec, the shell's watchdog): not left "checking".
trap '[ "$done" = 1 ] || finish timeout' EXIT
trap 'exit 1' TERM INT
write "$(jq -c '.checking = true' <<<"$prev")"

[ -n "$repo" ] || finish no-repo
version=$(cat "$version_file" 2>/dev/null) || finish no-version
jq -e 'type == "object"' >/dev/null 2>&1 <<<"$version" || finish bad-version
rev=$(jq -r '.rev // ""' <<<"$version")
# Deployed from a tree with uncommitted changes: rev is the commit they were
# made on (older builds wrote an all-zero rev instead).
if [ -z "$rev" ] || [[ $rev =~ ^0+$ ]]; then local_rev=Unknown; else local_rev=$rev; fi
branch=$(jq -r '.branch // "Unknown"' <<<"$version")
dirty=$(jq --arg r "$rev" '.dirty == true or ($r | test("^0+$"))' <<<"$version")

# Bounded, and never prompting (credentials, ssh host keys).
remote=$(GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10" \
  timeout 20 git ls-remote "$repo" refs/heads/main 2>/dev/null)
code=$?
[ "$code" = 124 ] && finish timeout
[ "$code" = 0 ] || finish unreachable
remote_rev=$(awk 'NR == 1 { print $1 }' <<<"$remote")
[ -n "$remote_rev" ] || remote_rev=Unknown

# An unknown local rev still gets compared: any remote commit is then an update.
available=false
[ "$remote_rev" != Unknown ] && [ "$local_rev" != "$remote_rev" ] && available=true

# The changelog is a bonus: the check worked without it (GitHub's rate limit).
changelog='[]'
if [ "$available" = true ] && [ "$branch" = refs/heads/main ] && [ "$local_rev" != Unknown ]; then
  # Only a GitHub repository's (https://github.com/OWNER/NAME): another
  # host's owner and name aren't GitHub's.
  IFS=/ read -r _ _ host owner name _ <<<"$repo"
  name=${name%.git}
  if [ "${host,,}" = github.com ] && [ -n "${owner:-}" ] && [ -n "$name" ]; then
    changelog=$(curl -sfL --max-time 15 "https://api.github.com/repos/$owner/$name/compare/$local_rev...$remote_rev" |
      jq -c '[.commits[]?.commit.message | split("\n")[0]]' 2>/dev/null) || changelog='[]'
    [ -n "$changelog" ] || changelog='[]'
  fi
fi

# Where main's build of the new revision is (automatic updates wait for it):
# this machine's `build (<host>)` job and the cache push, from GitHub's check
# runs. "passed": both done (the system comes from the cache, not built here);
# "pending": still running; "failed": this machine's build failed; "": not
# known (not GitHub, rate limit, no such job).
ci=""
if [ "$available" = true ]; then
  IFS=/ read -r _ _ host owner name _ <<<"$repo"
  name=${name%.git}
  if [ "${host,,}" = github.com ] && [ -n "${owner:-}" ] && [ -n "$name" ]; then
    machine=${NIXBOOK_HOSTNAME:-$(cat /proc/sys/kernel/hostname 2>/dev/null)}
    ci=$(curl -sfL --max-time 15 "https://api.github.com/repos/$owner/$name/commits/$remote_rev/check-runs?per_page=100" |
      jq -r --arg b "build ($machine)" '
        [.check_runs[]? | select(.name == $b or .name == "push-cache")] as $runs
        | ($runs | map(select(.name == $b)) | first) as $build
        | ($runs | map(select(.name == "push-cache")) | first) as $push
        | if $build == null then ""
          elif $build.status != "completed" then "pending"
          elif ($build.conclusion | IN("success", "skipped", "neutral") | not) then "failed"
          elif $push == null or $push.status != "completed" then "pending"
          else "passed" end' 2>/dev/null) || ci=""
  fi
fi

finish "" "$(jq -nc --arg l "$local_rev" --arg b "$branch" --argjson d "$dirty" --arg r "$remote_rev" \
  --argjson a "$available" --argjson c "$changelog" --arg ci "$ci" \
  '{localRev: $l, localBranch: $b, localDirty: $d, remoteRev: $r, available: $a, changelog: $c, ci: $ci}')"
