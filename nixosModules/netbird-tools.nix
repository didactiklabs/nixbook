{ pkgs, ... }:
let
  nswitch = pkgs.writeShellScriptBin "nswitch" ''
    set -euo pipefail
    PATH="${
      pkgs.lib.makeBinPath [
        pkgs.netbird
        pkgs.fzf
        pkgs.gawk
      ]
    }:$PATH"

    # Get the list of available networks
    networks=$(netbird networks list 2>/dev/null | awk '/ID:/ {print $3}')

    if [[ -z "$networks" ]]; then
      echo "Error: No Netbird networks found or netbird daemon not running." >&2
      exit 1
    fi

    # Use fzf to select a network
    selected=$(echo "$networks" | fzf --prompt="Select Netbird Network> ")

    if [[ -z "$selected" ]]; then
      echo "No network selected. Exiting."
      exit 1
    fi

    echo "Switching to Network: $selected..."

    if netbird network select "$selected" && netbird up; then
      echo "Successfully switched to $selected."
    else
      echo "Error: Failed to select or bring up $selected." >&2
      exit 1
    fi
  '';
in
{
  environment.systemPackages = [ nswitch ];
}
