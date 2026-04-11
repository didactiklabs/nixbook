{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customNixOSModules;
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
  options.customNixOSModules.netbird-tools = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to enable NetBird VPN client with the nswitch helper.

        NetBird is a WireGuard-based overlay network tool for connecting machines
        across different networks without port-forwarding or static IPs.

        This module:
        - Enables services.netbird (daemon only, no systray UI)
        - Installs nswitch: an fzf-based TUI that lists available NetBird network
          IDs (via `netbird networks list`) and switches to the selected one with
          `netbird network select && netbird up`

        Enabled by default on all machines.
      '';
    };
  };

  config = lib.mkIf cfg.netbird-tools.enable {
    services = {
      netbird = {
        enable = true;
        ui.enable = false;
      };
    };

    # Prevent NetworkManager from interfering with NetBird's WireGuard interface
    networking.networkmanager.unmanaged = [ "interface-name:wt*" ];

    environment.systemPackages = [ nswitch ];
  };
}
