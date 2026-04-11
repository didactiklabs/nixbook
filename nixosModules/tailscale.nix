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
    PATH="${
      pkgs.lib.makeBinPath [
        pkgs.iproute2
        pkgs.gawk
        pkgs.gnugrep
        pkgs.coreutils
      ]
    }:$PATH"

    # Collect all IPv4 subnets directly connected to physical interfaces,
    # excluding VPN tunnels (tailscale0, wt*) and loopback.
    get_local_subnets() {
      ip -4 route show proto kernel \
        | grep -vE 'dev (tailscale0|wt[^ ]*|lo) ' \
        | awk '{print $1}' \
        | grep '/'
    }

    # Remove any route in Tailscale's policy-routing table (52) on tailscale0
    # that exactly matches a locally-connected subnet.
    fix_routes() {
      local local_subnets
      local_subnets=$(get_local_subnets)
      if [[ -z "$local_subnets" ]]; then
        return
      fi

      while read -r ts_route; do
        # ts_route is a subnet like "10.0.0.0/24" from table 52 via tailscale0
        local subnet
        subnet=$(echo "$ts_route" | awk '{print $1}')
        # Check if this tailscale route conflicts with a local subnet
        if echo "$local_subnets" | grep -qxF "$subnet"; then
          echo "Removing conflicting route $subnet dev tailscale0 from table 52"
          ip route del "$subnet" dev tailscale0 table 52 2>/dev/null || true
        fi
      done < <(ip route show table 52 dev tailscale0 2>/dev/null)
    }

    # Run once at startup to clean up any pre-existing conflicts
    fix_routes

    # Then monitor for route changes and re-check on every tailscale0 event
    ip monitor route | while read -r line; do
      echo "$line" | grep -q "dev tailscale0" || continue
      fix_routes
    done
  '';
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
    # Enable IPv6 forwarding for exit node / subnet routing support.
    boot.kernel.sysctl = {
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
    systemd.services = {
      # Force tailscaled to use native nftables instead of the iptables-compat
      # translation layer. Critical for clean nftables-only systems.
      tailscaled.serviceConfig.Environment = [
        "TS_DEBUG_FIREWALL_MODE=nftables"
      ];
      # Persistent route-fix daemon: monitors route changes and removes Tailscale
      # routes (table 52) that conflict with the physical LAN subnet, scoped to
      # the physical default gateway so NetBird (wt*) routes are left alone.
      tailscale-fix-routes = {
        enable = true;
        after = [ "tailscaled.service" ];
        bindsTo = [ "tailscaled.service" ];
        partOf = [ "tailscaled.service" ];
        wantedBy = [ "tailscaled.service" ];
        serviceConfig = {
          ExecStart = "${tailscale-fix-routes}/bin/tailscale-fix-routes";
          Restart = "always";
          RestartSec = 5;
        };
      };
    };
  };
}
