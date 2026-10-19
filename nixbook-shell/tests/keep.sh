#!/usr/bin/env bash
# Tests for the Google Keep sync of the notes (scripts/keep-sync.py):
#   - the merge (tests/keep-tests.py): a note's title and text, the
#     checklists, what is pushed and what comes back, the conflicts, the
#     deletions (not synced) and the two directions;
#   - the commands: the status (no account, then one), the logout, a sync
#     without an account, a wrong command.
# Needs bash, python3 and jq. Run: bash tests/keep.sh
set -euo pipefail
export -n out 2>/dev/null || true

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/scripts/keep-sync.py"
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

export NIXBOOK_KEEP_SECRETS_DIR="$tmp/secrets"
export XDG_STATE_HOME="$tmp/state"

# The shell's Python environment (with gkeepapi) when it is given: the tests
# about the notes' writing in Keep need the library; the others don't.
python="${NIXBOOK_KEEP_PYTHON:-python3}"

# -- The merge ----------------------------------------------------------------

if "$python" "$root/tests/keep-tests.py" "$script" >"$tmp/merge.log" 2>&1; then
  pass "the merge (tests/keep-tests.py)"
else
  fail "the merge (tests/keep-tests.py)" "$(cat "$tmp/merge.log")"
fi

# -- The commands -------------------------------------------------------------

out=$("$python" "$script" status) || fail "status answers"
expect_eq "no account yet" "false" "$(jq -r '.configured' <<<"$out")"
expect_eq "no email yet" "" "$(jq -r '.email' <<<"$out")"

# An account in the keyring (the tests keep it in a file).
mkdir -p "$NIXBOOK_KEEP_SECRETS_DIR"
printf '%s' '{"email": "tester@example.com", "token": "secret"}' \
  >"$NIXBOOK_KEEP_SECRETS_DIR/google-keep"
out=$("$python" "$script" status) || fail "status answers with an account"
expect_eq "the account is found" "true" "$(jq -r '.configured' <<<"$out")"
expect_eq "the account's email is shown" "tester@example.com" "$(jq -r '.email' <<<"$out")"

# A sync without a working account says so (it can't reach Google here).
if "$python" -c "import gkeepapi" 2>/dev/null; then
  expected_error="Google refused the account: the master token is not valid"
  expected_code=3
else
  expected_error="gkeepapi isn't installed (the shell's package is broken)"
  expected_code=5
fi
if "$python" "$script" sync <<<'{"notes": []}' >"$tmp/sync" 2>/dev/null; then
  fail "a sync without an account fails"
else
  code=$?
  expect_eq "a sync without an account says why" "$expected_error" \
    "$(jq -r '.error' <"$tmp/sync")"
  expect_eq "a sync without an account exits with $expected_code" "$expected_code" "$code"
fi

# The logout forgets the account.
"$python" "$script" logout >/dev/null || fail "logout answers"
out=$("$python" "$script" status)
expect_eq "the account is gone" "false" "$(jq -r '.configured' <<<"$out")"

# A wrong command is refused.
if "$python" "$script" nope >/dev/null 2>&1; then
  fail "a wrong command fails"
else
  expect_eq "a wrong command exits with 1" "1" "$?"
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures failed" >&2
  exit 1
fi
echo "keep: every test passed"
