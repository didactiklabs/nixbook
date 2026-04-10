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
  # tailscale-fix-routes = pkgs.writeShellScriptBin "tailscale-fix-routes" ''
  #   set -euo pipefail
  #   ip monitor route | while read -r line; do
  #       for MASK in 16 24; do
  #           SUBNET=$(ip -4 route show default | awk '{print $3}' | cut -d. -f1-3).0/$MASK
  #           if echo "$line" | grep -q "$SUBNET dev tailscale0"; then
  #               if ip route show table 52 | grep -q "$SUBNET dev tailscale0"; then
  #                   ip route del $SUBNET dev tailscale0 table 52
  #               fi
  #           fi
  #       done
  #   done
  # '';
in
{
  options.customNixOSModules.tailscale = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to enable Tailscale VPN with exit node support and native nftables.

        Tailscale is a mesh VPN built on WireGuard.  This module configures:

        - services.tailscale with useRoutingFeatures = "both" for full exit node
          and subnet router support
        - Native nftables backend via TS_DEBUG_FIREWALL_MODE=nftables to avoid
          iptables-compat translation layer issues
        - IP forwarding (IPv4 + IPv6) and loose reverse-path filtering for exit
          node traffic
        - Firewall: trusts the tailscale0 interface and allows the Tailscale UDP
          port through
        - tswitch (fzf-based TUI): interactive CLI tool to list and switch between
          Tailnets using `tailscale switch`, surfaced via fzf for fuzzy selection

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
    services.tailscale = {
      enable = true;
    };
    # Enable IP forwarding for exit node / subnet routing support.
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
    };
    networking.firewall = {
      # Always allow traffic from the Tailscale network.
      trustedInterfaces = [ "tailscale0" ];
      # Allow the Tailscale UDP port through the firewall.
      allowedUDPPorts = [ config.services.tailscale.port ];
      # Loose reverse-path filtering: required because exit node traffic arrives
      # on tailscale0 but replies leave via the physical interface, which strict
      # rp_filter would drop.
      checkReversePath = "loose";
    };
    # Force tailscaled to use native nftables instead of the iptables-compat
    # translation layer. Critical for clean nftables-only systems.
    systemd.services.tailscaled.serviceConfig.Environment = [
      "TS_DEBUG_FIREWALL_MODE=nftables"
    ];
  };
}
