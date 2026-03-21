{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customNixOSModules;
  tailscale-switch = pkgs.writeShellScriptBin "tswitch" ''
    # Get the list of available Tailnets
    tailnet_list=$(tailscale switch --list | tail -n +2 2>/dev/null)

    # Use fzf to select a Tailnet
    selected_tailnet=$(echo "$tailnet_list" | fzf --prompt="Select a Tailnet> ")

    if [[ -z "$selected_tailnet" ]]; then
      echo "No Tailnet selected. Exiting."
      exit 1
    fi

    tailnet_name=$(echo "$selected_tailnet" | awk '{gsub("\\*", "", $2); print $2}')
    echo "$tailnet_name"
    echo "Switching to Tailnet: $tailnet_name..."

    if tailscale switch "$tailnet_name"; then
      echo "Successfully switched to $tailnet_name."
    else
      echo "Failed to switch to $tailnet_name."
    fi
  '';
  tailscale-fix-routes = pkgs.writeShellScriptBin "tailscale-fix-routes" ''
    set -euo pipefail
    ip monitor route | while read -r line; do
        for MASK in 16 24; do
            SUBNET=$(ip -4 route show default | awk '{print $3}' | cut -d. -f1-3).0/$MASK
            if echo "$line" | grep -q "$SUBNET dev tailscale0"; then
                if ip route show table 52 | grep -q "$SUBNET dev tailscale0"; then
                    ip route del $SUBNET dev tailscale0 table 52
                fi
            fi
        done
    done
  '';
in
{
  options.customNixOSModules.tailscale = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to enable Tailscale VPN with route-conflict workarounds.

        Tailscale is a mesh VPN built on WireGuard.  When multiple Tailnets are
        configured, subnet routes can conflict with the host's default gateway,
        breaking connectivity.  This module works around that by:

        - tailscale-fix-routes service: a persistent systemd unit that monitors
          the kernel route table via `ip monitor route` and removes conflicting
          /16 and /24 Tailscale subnet routes from routing table 52 as soon as
          they appear
        - tswitch (fzf-based TUI): interactive CLI tool to list and switch between
          Tailnets using `tailscale switch`, surfaced via fzf for fuzzy selection
        - Installs the tailscale package and enables services.tailscale

        Enabled by default on all machines.
      '';
    };
  };

  config = lib.mkIf cfg.tailscale.enable {
    environment = {
      systemPackages = [
        tailscale-switch
        pkgs.tailscale
      ];
    };
    services.tailscale.enable = true;
    systemd = {
      services.tailscale-fix-routes = {
        enable = true;
        path = [
          pkgs.iproute2
          pkgs.busybox
        ];
        wantedBy = [ "multi-user.target" ];
        requires = [ "default.target" ];
        serviceConfig = {
          ExecStart = "${tailscale-fix-routes}/bin/tailscale-fix-routes";
          Restart = "always";
        };
      };
    };
  };
}
