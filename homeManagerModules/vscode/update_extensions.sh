#!/usr/bin/env bash
# Script amélioré pour mettre à jour les extensions VSCode dans extensionsList.nix
# Usage: ./update_extensions.sh [--all|extension.id]

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
EXTENSIONS_FILE="$SCRIPT_DIR/extensionsList.nix"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Fetch extension metadata from VSCode Marketplace API
fetch_extension_info() {
    local publisher="$1"
    local name="$2"

    local json_response
    json_response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "Accept: application/json;api-version=3.0-preview.1" \
        -d "{\"filters\":[{\"criteria\":[{\"filterType\":7,\"value\":\"$publisher.$name\"}]}],\"flags\":914}" \
        https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery)

    if [ -z "$json_response" ]; then
        log_error "Failed to fetch data for $publisher.$name"
        return 1
    fi

    echo "$json_response"
}

# Get latest version from marketplace
get_latest_version() {
    local publisher="$1"
    local name="$2"
    local json_response="$3"

    echo "$json_response" | jq -r '.results[0].extensions[0].versions[0].version' 2>/dev/null || echo ""
}

# Download and calculate SHA256 hash
calculate_sha256() {
    local publisher="$1"
    local name="$2"
    local version="$3"

    local url="https://$publisher.gallery.vsassets.io/_apis/public/gallery/publisher/$publisher/extension/$name/$version/assetbyname/Microsoft.VisualStudio.Services.VSIXPackage"

    local temp_file
    temp_file=$(mktemp)

    if ! curl -sSL -o "$temp_file" "$url" 2>/dev/null; then
        rm -f "$temp_file"
        log_error "Failed to download $publisher.$name@$version"
        return 1
    fi

    local hash
    hash=$(nix-hash --flat --base32 --type sha256 "$temp_file" 2>/dev/null)
    rm -f "$temp_file"

    if [ -z "$hash" ]; then
        log_error "Failed to calculate hash for $publisher.$name@$version"
        return 1
    fi

    echo "$hash"
}

# Update a single extension in the file
update_extension() {
    local publisher="$1"
    local name="$2"

    log_info "Updating $publisher.$name..."

    local json_response
    json_response=$(fetch_extension_info "$publisher" "$name")

    if [ -z "$json_response" ]; then
        return 1
    fi

    local latest_version
    latest_version=$(get_latest_version "$publisher" "$name" "$json_response")

    if [ -z "$latest_version" ]; then
        log_error "Could not determine latest version for $publisher.$name"
        return 1
    fi

    log_info "Latest version: $latest_version"

    local sha256_hash
    sha256_hash=$(calculate_sha256 "$publisher" "$name" "$latest_version")

    if [ -z "$sha256_hash" ]; then
        return 1
    fi

    # Update the entry in extensionsList.nix
    # This is a simple sed replacement - might need adjustment based on formatting
    local temp_file
    temp_file=$(mktemp)

    # Find and replace the extension block
    awk -v publisher="$publisher" -v name="$name" -v version="$latest_version" -v sha256="$sha256_hash" '
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
    ' "$EXTENSIONS_FILE" > "$temp_file"

    mv "$temp_file" "$EXTENSIONS_FILE"

    log_info "✓ Updated $publisher.$name to version $latest_version"
}

# Parse current extensions from extensionsList.nix
get_current_extensions() {
    grep -E '^\s+publisher\s*=|^\s+name\s*=' "$EXTENSIONS_FILE" | \
    sed 's/.*"\(.*\)".*/\1/' | \
    paste -d'.' - -
}

# Main function
main() {
    if [ ! -f "$EXTENSIONS_FILE" ]; then
        log_error "extensionsList.nix not found at $EXTENSIONS_FILE"
        exit 1
    fi

    # Check dependencies
    for cmd in curl jq nix-hash; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command '$cmd' not found"
            exit 1
        fi
    done

    if [ $# -eq 0 ] || [ "$1" = "--all" ]; then
        log_info "Updating all extensions..."

        while IFS='.' read -r publisher name; do
            update_extension "$publisher" "$name" || log_warn "Failed to update $publisher.$name"
            sleep 0.5  # Be nice to the API
        done < <(get_current_extensions)

        log_info "All extensions updated!"
    else
        # Update specific extension
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
