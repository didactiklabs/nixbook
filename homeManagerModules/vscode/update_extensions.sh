#!/usr/bin/env bash
# Enhanced script to update VSCode extensions in extensionsList.nix
# Automatically detects the VSCode version and only selects compatible extensions.
#
# Usage:
#   ./update_extensions.sh [--all]                      # Update all extensions
#   ./update_extensions.sh publisher.name               # Update a specific extension
#   ./update_extensions.sh --vscode-version 1.96.0 ...  # Force a specific VSCode version

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
EXTENSIONS_FILE="$SCRIPT_DIR/extensionsList.nix"
VSCODE_VERSION=""

# Output colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
  echo -e "${BLUE}[DEBUG]${NC} $1"
}

# ── Semver helpers ──────────────────────────────────────────────────────
# Split "1.85.2" → sets MAJ, MIN, PAT
split_semver() {
  local ver="$1"
  # Strip leading 'v' if present
  ver="${ver#v}"
  # Strip anything after a dash (pre-release tags)
  # e.g. 1.109.0-20260124 → 1.109.0
  ver="${ver%%-*}"
  MAJ="${ver%%.*}"
  local rest="${ver#*.}"
  MIN="${rest%%.*}"
  PAT="${rest#*.}"
  # If no patch component, default to 0
  [[ $PAT == "$MIN" ]] && PAT=0
  # Ensure all parts are numeric
  MAJ="${MAJ:-0}"
  MIN="${MIN:-0}"
  PAT="${PAT:-0}"
}

# Return 0 if $1 >= $2 (both semver strings)
semver_ge() {
  local a_maj a_min a_pat b_maj b_min b_pat
  split_semver "$1"
  a_maj=$MAJ
  a_min=$MIN
  a_pat=$PAT
  split_semver "$2"
  b_maj=$MAJ
  b_min=$MIN
  b_pat=$PAT

  if ((a_maj > b_maj)); then return 0; fi
  if ((a_maj < b_maj)); then return 1; fi
  if ((a_min > b_min)); then return 0; fi
  if ((a_min < b_min)); then return 1; fi
  if ((a_pat >= b_pat)); then return 0; fi
  return 1
}

# Check whether $vscode_ver satisfies the engine constraint $constraint.
# Supported formats: *, ^X.Y.Z, >=X.Y.Z, X.Y.Z (exact)
engine_satisfies() {
  local vscode_ver="$1"
  local constraint="$2"

  # Wildcard - always compatible
  if [[ $constraint == "*" ]]; then
    return 0
  fi

  # ^X.Y.Z - vscode_ver must be >= X.Y.Z with the same major (unless major is 0)
  if [[ $constraint == "^"* ]]; then
    local min_ver="${constraint#^}"
    split_semver "$min_ver"
    local c_maj=$MAJ
    split_semver "$vscode_ver"
    local v_maj=$MAJ

    # Major version must match (standard ^semver behavior for major >= 1)
    if ((c_maj >= 1 && v_maj != c_maj)); then
      return 1
    fi
    semver_ge "$vscode_ver" "$min_ver"
    return $?
  fi

  # >=X.Y.Z
  if [[ $constraint == ">="* ]]; then
    local min_ver="${constraint#>=}"
    semver_ge "$vscode_ver" "$min_ver"
    return $?
  fi

  # Plain version - treat as >=
  semver_ge "$vscode_ver" "$constraint"
  return $?
}

# ── Detect VSCode version ──────────────────────────────────────────────
detect_vscode_version() {
  # 1) Try the 'code' binary
  if command -v code &>/dev/null; then
    local ver
    ver=$(code --version 2>/dev/null | grep -m1 '^[0-9]\+\.[0-9]\+')
    if [[ -n $ver ]]; then
      echo "$ver"
      return 0
    fi
  fi

  # 2) Try codium
  if command -v codium &>/dev/null; then
    local ver
    ver=$(codium --version 2>/dev/null | grep -m1 '^[0-9]\+\.[0-9]\+')
    if [[ -n $ver ]]; then
      echo "$ver"
      return 0
    fi
  fi

  return 1
}

# ── Marketplace API helpers ─────────────────────────────────────────────

# Fetch extension metadata – flags 145 = IncludeVersions(1) + IncludeVersionProperties(16) + IncludeAssetUri(128)
# This returns ALL versions with their properties so we can filter by engine.
fetch_extension_info() {
  local publisher="$1"
  local name="$2"

  local json_response
  json_response=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -H "Accept: application/json;api-version=3.0-preview.1" \
    -d "{\"filters\":[{\"criteria\":[{\"filterType\":7,\"value\":\"$publisher.$name\"}]}],\"flags\":145}" \
    https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery)

  if [ -z "$json_response" ]; then
    log_error "Failed to fetch data for $publisher.$name"
    return 1
  fi

  echo "$json_response"
}

# Given the full JSON response, find the latest version whose
# "Microsoft.VisualStudio.Code.Engine" property satisfies $VSCODE_VERSION.
# Pre-release / insiders versions (flagged via the Marketplace API) are skipped.
get_compatible_version() {
  local publisher="$1"
  local name="$2"
  local json_response="$3"

  # Extract "version engine_constraint prerelease_flag" for every published version.
  # The API already returns versions sorted newest-first.
  # A version is considered pre-release if it has the
  # "Microsoft.VisualStudio.Code.PreRelease" property set to "true".
  local versions_info
  versions_info=$(echo "$json_response" | jq -r '
        .results[0].extensions[0].versions[]
        | {
            version: .version,
            engine: (
              [ .properties[]? | select(.key == "Microsoft.VisualStudio.Code.Engine") | .value ]
              | if length > 0 then .[0] else "*" end
            ),
            prerelease: (
              [ .properties[]? | select(.key == "Microsoft.VisualStudio.Code.PreRelease") | .value ]
              | if length > 0 then .[0] else "false" end
            )
          }
        | "\(.version) \(.engine) \(.prerelease)"
    ' 2>/dev/null)

  if [ -z "$versions_info" ]; then
    return 1
  fi

  while IFS=' ' read -r ver engine prerelease; do
    # Skip pre-release versions
    if [[ $prerelease == "true" ]]; then
      continue
    fi
    if engine_satisfies "$VSCODE_VERSION" "$engine"; then
      echo "$ver"
      return 0
    fi
  done <<<"$versions_info"

  # No compatible version found
  return 1
}

# Download and calculate SHA256 hash
# Prefetch the VSIX through Nix and return the SRI hash it will expect at build time.
calculate_sha256() {
  local publisher="$1"
  local name="$2"
  local version="$3"

  local url="https://$publisher.gallery.vsassets.io/_apis/public/gallery/publisher/$publisher/extension/$name/$version/assetbyname/Microsoft.VisualStudio.Services.VSIXPackage"

  local hash
  hash=$(nix store prefetch-file --json "$url" 2>/dev/null | jq -r '.hash')

  if [ -z "$hash" ] || [ "$hash" = "null" ]; then
    log_error "Failed to prefetch $publisher.$name@$version"
    return 1
  fi

  echo "$hash"
}

# ── Update logic ────────────────────────────────────────────────────────

update_extension() {
  local publisher="$1"
  local name="$2"

  log_info "Updating $publisher.$name..."

  local json_response
  json_response=$(fetch_extension_info "$publisher" "$name")

  if [ -z "$json_response" ]; then
    return 1
  fi

  # Find the latest version compatible with our VSCode version
  local target_version
  target_version=$(get_compatible_version "$publisher" "$name" "$json_response")

  if [ -z "$target_version" ]; then
    log_error "No version of $publisher.$name is compatible with VSCode $VSCODE_VERSION"
    return 1
  fi

  # Also grab the absolute latest version for informational purposes
  local absolute_latest
  absolute_latest=$(echo "$json_response" | jq -r '.results[0].extensions[0].versions[0].version' 2>/dev/null || echo "?")

  if [[ $target_version != "$absolute_latest" ]]; then
    log_warn "Latest ($absolute_latest) is not compatible with VSCode $VSCODE_VERSION → using $target_version"
  else
    log_info "Latest version $target_version is compatible ✓"
  fi

  local sha256_hash
  sha256_hash=$(calculate_sha256 "$publisher" "$name" "$target_version")

  if [ -z "$sha256_hash" ]; then
    return 1
  fi

  # Update the extension entry in extensionsList.nix
  local temp_file
  temp_file=$(mktemp)

  awk -v publisher="$publisher" -v name="$name" -v version="$target_version" -v sha256="$sha256_hash" '
    BEGIN { in_block=0; found=0 }
    /^    \{$/ { in_block=1; block=""; next }
    in_block {
        block = block $0 "\n"
        if (/^    \}$/) {
            if (block ~ "publisher = \"" publisher "\"" && block ~ "name = \"" name "\"") {
                printf "    {\n"
                printf "      name = \"%s\";\n", name
                printf "      publisher = \"%s\";\n", publisher
                printf "      version = \"%s\";\n", version
                printf "      sha256 = \"%s\";\n", sha256
                printf "    }\n"
                found=1
            } else {
                printf "    {\n%s", block
            }
            in_block=0
            block=""
            next
        }
    }
    !in_block { print }
    ' "$EXTENSIONS_FILE" >"$temp_file"

  mv "$temp_file" "$EXTENSIONS_FILE"

  log_info "✓ Updated $publisher.$name to $target_version (VSCode $VSCODE_VERSION)"
}

# Parse current extensions from extensionsList.nix.
# Returns lines of "publisher.name" in the correct order.
get_current_extensions() {
  awk '
        /name = "/ { name=$0; gsub(/.*name = "|".*/, "", name) }
        /publisher = "/ { pub=$0; gsub(/.*publisher = "|".*/, "", pub); print pub "." name }
    ' "$EXTENSIONS_FILE"
}

# ── Main ────────────────────────────────────────────────────────────────

main() {
  if [ ! -f "$EXTENSIONS_FILE" ]; then
    log_error "extensionsList.nix not found at $EXTENSIONS_FILE"
    exit 1
  fi

  # Check required dependencies
  for cmd in curl jq nix; do
    if ! command -v "$cmd" &>/dev/null; then
      log_error "Required command '$cmd' not found"
      exit 1
    fi
  done

  # Parse the --vscode-version flag
  local positional_args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --vscode-version)
      VSCODE_VERSION="$2"
      shift 2
      ;;
    *)
      positional_args+=("$1")
      shift
      ;;
    esac
  done
  set -- "${positional_args[@]+"${positional_args[@]}"}"

  # Auto-detect VSCode version if not explicitly provided
  if [ -z "$VSCODE_VERSION" ]; then
    VSCODE_VERSION=$(detect_vscode_version) || true
    if [ -z "$VSCODE_VERSION" ]; then
      log_error "Could not detect VSCode version. Use --vscode-version X.Y.Z"
      exit 1
    fi
  fi

  log_info "Target VSCode version: $VSCODE_VERSION"

  if [ $# -eq 0 ] || [ "$1" = "--all" ]; then
    log_info "Updating all extensions..."

    while IFS='.' read -r publisher name; do
      update_extension "$publisher" "$name" || log_warn "Failed to update $publisher.$name"
      sleep 0.5 # Rate-limit API requests
    done < <(get_current_extensions)

    log_info "All extensions updated!"
  else
    # Update a specific extension
    local publisher="${1%%.*}"
    local name="${1#*.}"

    if [ "$publisher" = "$name" ]; then
      log_error "Invalid extension format. Use: publisher.name"
      exit 1
    fi

    update_extension "$publisher" "$name"
  fi

  log_info "Done! Don't forget to run: nixfmt $EXTENSIONS_FILE"
}

main "$@"
