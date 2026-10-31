#!/usr/bin/env bash
# Pushes the built systems to the S3 binary cache (build.yaml's push-cache
# job), only the paths cache.nixos.org doesn't serve.
#
#   push-cache.sh BUILD...    (store paths: the systems' toplevels)
#
# `nix copy` to a binary cache refuses a path whose references aren't in
# that same cache ("cannot add ... because the reference ... does not
# exist"), so it can't push a nixbook path without the stock packages it
# references. The machines don't need those in S3: they substitute from
# cache.nixos.org too. So the paths are copied to a local staging cache
# where the references' .narinfo files (fetched from cache.nixos.org, or
# from our cache when it has them already) stand in for them; then only
# the paths built here go up to S3 (their NARs first, then their narinfos,
# so a client never sees a narinfo without its NAR).
#
# The staging is done in batches of about PUSH_BATCH_MB of NARs, each
# uploaded and its NARs deleted before the next: $RUNNER_TEMP is a tmpfs
# on the runner, and staging a nixpkgs bump's ~1000 paths at once filled
# it ("No space left on device", every push for days). Batches follow
# `nix-store -qR`'s order (references first), and the narinfos stay in
# the stage, so each batch's references are always there.
#
# Env: CACHE_KEY (the signing key's file), CACHE_URL (the cache's public
# https URL), S3_BUCKET, S3_ENDPOINT, and AWS_ACCESS_KEY_ID /
# AWS_SECRET_ACCESS_KEY for the upload. UPLOAD=0 skips it (tests).
set -euo pipefail

: "${CACHE_URL:=https://s3.didactiklabs.io/nix-cache}"
: "${S3_BUCKET:=nix-cache}"
: "${S3_ENDPOINT:=https://s3.didactiklabs.io}"
: "${PUSH_BATCH_MB:=1024}"
upstream_url=https://cache.nixos.org
work=${RUNNER_TEMP:-$(mktemp -d)}/push-cache
rm -rf "$work"
mkdir -p "$work/stage"

nix path-info --recursive "$@" | sort -u >"$work/closure"

# present LIST STORE: the paths of LIST that STORE has.
present() {
  # Not "out": nix-shell exports $out, and a local of that name stays
  # exported, so its megabytes of JSON made every later exec fail with
  # "Argument list too long".
  local info
  mapfile -t paths <"$1"
  [ "${#paths[@]}" -gt 0 ] || return 0
  # Missing paths: null values (Nix >= 2.19), or "valid": false entries in
  # older Nix's array output. A store that can't be queried has none.
  info=$(nix path-info --json --option narinfo-cache-negative-ttl 0 --store "$2" "${paths[@]}" 2>/dev/null) || true
  [ -n "$info" ] || return 0
  jq -r 'if type == "array" then .[] | select(.valid != false) | .path
    else to_entries[] | select(.value != null) | .key end' <<<"$info" | sort -u
}

present "$work/closure" "$upstream_url" >"$work/upstream"
comm -23 "$work/closure" "$work/upstream" >"$work/ours"
present "$work/ours" "$CACHE_URL" >"$work/pushed"
comm -23 "$work/ours" "$work/pushed" >"$work/todo"
echo "$(wc -l <"$work/todo") paths to push ($(wc -l <"$work/closure") in the closure," \
  "$(wc -l <"$work/upstream") on cache.nixos.org, $(wc -l <"$work/pushed") already pushed)"
if [ ! -s "$work/todo" ]; then
  exit 0
fi
# References first (nix-store -qR's order), so batches can follow it.
nix-store --query --requisites "$@" | grep -Fxf "$work/todo" >"$work/todo-ordered"
mapfile -t todo <"$work/todo-ordered"

# The references outside what is pushed now: their narinfos, staged.
nix-store --query --references "${todo[@]}" | sort -u | comm -23 - "$work/todo" >"$work/refs"
while read -r ref; do
  h=$(basename "$ref" | cut -d- -f1)
  curl -sfL --retry 3 "$upstream_url/$h.narinfo" -o "$work/stage/$h.narinfo" ||
    curl -sfL --retry 3 "$CACHE_URL/$h.narinfo" -o "$work/stage/$h.narinfo" || {
    echo "::error::$ref is neither on cache.nixos.org nor in our cache" >&2
    exit 1
  }
done <"$work/refs"
echo "$(wc -l <"$work/refs") references staged"

key=${CACHE_KEY:+&secret-key=$CACHE_KEY}

# Path-style requests: the endpoint isn't AWS.
export AWS_CONFIG_FILE="$work/aws-config"
printf '[default]\nregion = us-east-1\ns3 =\n  addressing_style = path\n' >"$AWS_CONFIG_FILE"
upload() { # DIR DEST CONTENT-TYPE
  aws s3 sync --endpoint-url "$S3_ENDPOINT" --only-show-errors --content-type "$3" "$1" "s3://$S3_BUCKET/$2"
}

# push PATH...: stage these paths, upload them, drop their NARs.
pushed=0
push() {
  local p h attempt
  nix copy --no-recursive --to "file://$work/stage?compression=zstd$key" "$@"
  # What goes up: the NARs, and the narinfos of these paths only. The
  # narinfos stay staged: later batches reference these paths.
  rm -rf "$work/up"
  mkdir -p "$work/up/info"
  for p in "$@"; do
    h=$(basename "$p" | cut -d- -f1)
    cp "$work/stage/$h.narinfo" "$work/up/info/"
  done
  mv "$work/stage/nar" "$work/up/nar"
  pushed=$((pushed + $#))
  echo "staged $(find "$work/up/nar" -type f | wc -l) NARs ($(du -sh "$work/up/nar" | cut -f1)), $pushed/${#todo[@]} paths"
  if [ "${UPLOAD:-1}" = 1 ]; then
    # sync skips what is already there: a retry resumes.
    for attempt in 1 2 3 4 5; do
      if upload "$work/up/nar" nar application/x-nix-nar && upload "$work/up/info" "" text/x-nix-narinfo; then
        break
      fi
      if [ "$attempt" = 5 ]; then
        echo "::error::the upload failed after 5 attempts"
        exit 1
      fi
      echo "::warning::upload attempt $attempt failed, retrying in $((attempt * 30))s"
      sleep $((attempt * 30))
    done
  fi
  rm -rf "$work/up"
}

# Batches of about PUSH_BATCH_MB of NARs (uncompressed: an upper bound).
nix path-info --json "${todo[@]}" |
  jq -r 'if type == "array" then .[] | "\(.path) \(.narSize)"
    else to_entries[] | "\(.key) \(.value.narSize)" end' >"$work/sizes"
declare -A size
while read -r p s; do size[$p]=$s; done <"$work/sizes"
budget=$((PUSH_BATCH_MB * 1024 * 1024))
batch=()
batch_size=0
for p in "${todo[@]}"; do
  if [ ${#batch[@]} -gt 0 ] && [ $((batch_size + ${size[$p]})) -gt "$budget" ]; then
    push "${batch[@]}"
    batch=()
    batch_size=0
  fi
  batch+=("$p")
  batch_size=$((batch_size + ${size[$p]}))
done
push "${batch[@]}"
echo "pushed ${#todo[@]} paths"
