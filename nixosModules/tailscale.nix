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
    # https://github.com/tailscale/tailscale/issues/1227
    #
    # When using an exit node that also advertises the local LAN subnet
    # (e.g. a router running Tailscale), Tailscale adds that subnet to its
    # policy-routing table (52) pointing at tailscale0.  Since table 52 is
    # consulted before the main table, LAN traffic — including DNS to the
    # gateway — gets sucked into the tunnel and blackholed.
    #
    # Instead of deleting Tailscale's routes (which it immediately re-adds,
    # creating a fight loop), we inject "throw" routes into table 52 for
    # every locally-connected subnet.  A throw route tells the kernel
    # "this destination is not in this table — try the next rule", so
    # traffic falls through to the main table and uses the physical
    # interface.  Throw routes coexist with Tailscale's device routes
    # and the kernel prefers the throw (same prefix, but throw wins over
    # unicast-via-device in route selection).
    PATH="${
      pkgs.lib.makeBinPath [
        pkgs.iproute2
        pkgs.gawk
        pkgs.gnugrep
        pkgs.coreutils
      ]
    }:$PATH"

    # Remove ALL throw routes from table 52.  We are the only entity
    # that adds throw routes there (Tailscale itself adds unicast/device
    # routes), so a blanket cleanup is safe and avoids the need to track
    # individual entries.  This also correctly cleans up stale routes
    # left over from a previous service instance.
    cleanup_routes() {
      local routes
      routes=$(ip -4 route show table 52 2>/dev/null | grep "^throw " || true)
      if [[ -n "$routes" ]]; then
        echo "Cleaning up throw routes from table 52..."
        while IFS= read -r route; do
          local subnet
          subnet=$(echo "$route" | awk '{print $2}')
          echo "Removing throw route for $subnet from table 52"
          ip route del throw "$subnet" table 52 2>/dev/null || true
        done <<< "$routes"
      fi
    }

    # Clean up throw routes when the service stops (e.g. tailscaled goes
    # down and systemd tears us down via bindsTo).  TERM/INT must exit
    # (which runs the EXIT trap): a trap that only cleans up lets the
    # script carry on looping, and systemd then waits out the full stop
    # timeout before SIGKILL — a 90 s hang on every shutdown.
    monitor_pid=""
    on_exit() {
      [[ -n "$monitor_pid" ]] && kill "$monitor_pid" 2>/dev/null
      cleanup_routes
    }
    trap on_exit EXIT
    trap 'exit 0' TERM INT

    # Collect all IPv4 subnets directly connected to physical interfaces,
    # excluding VPN tunnels and loopback.  NetBird's WireGuard interfaces
    # (wt*) are explicitly excluded so our throw routes never cover
    # NetBird-managed subnets.
    get_local_subnets() {
      ip -4 route show proto kernel \
        | grep -vE 'dev (tailscale0|wt[^ ]*|lo) ' \
        | awk '{print $1}' \
        | grep '/' || true
    }

    # Returns 0 while Tailscale is routing: it has device routes on
    # tailscale0 in table 52.  `tailscale down` (or a stopped/logged-out
    # node) removes them.  Reading the kernel state instead of running
    # `tailscale status` keeps each check cheap and race-free: routes can
    # land before the backend reports Running.
    is_tailscale_routing() {
      [[ -n "$(ip -4 route show table 52 dev tailscale0 2>/dev/null)" ]]
    }

    # Ensure a throw route exists in table 52 for each local subnet.
    # This makes traffic to local subnets skip table 52 and fall through
    # to the main table, where the physical interface route lives.
    fix_routes() {
      local local_subnets
      local_subnets=$(get_local_subnets)
      if [[ -z "$local_subnets" ]]; then
        return
      fi

      while IFS= read -r subnet; do
        [[ -z "$subnet" ]] && continue
        # Add throw route if not already present
        if ! ip route show table 52 "$subnet" 2>/dev/null | grep -q "^throw"; then
          echo "Adding throw route for $subnet in table 52"
          ip route replace throw "$subnet" table 52 2>/dev/null || true
        fi
      done <<< "$local_subnets"
    }

    sync_routes() {
      if is_tailscale_routing; then
        fix_routes
      else
        cleanup_routes
      fi
    }

    # Event-driven, no polling: re-check whenever a route changes on
    # tailscale0 (Tailscale coming up, re-adding its subnet route after
    # we threw it, or going down).  When Tailscale stops routing, clean
    # up the throw routes so the routing table is left in a clean state
    # for other VPNs (NetBird).  The monitor is started before the
    # initial sync so no change can slip in between.  Reading it through
    # a file descriptor keeps the loop in the main shell, so the EXIT
    # trap has full access to cleanup_routes (and stops the monitor).
    exec 3< <(ip monitor route)
    monitor_pid=$!
    sync_routes
    while IFS= read -r line <&3; do
      case "$line" in
        *tailscale0*) sync_routes ;;
      esac
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
      # Persistent route-fix daemon: monitors route changes and injects "throw"
      # routes into Tailscale's table 52 for locally-connected subnets, so LAN
      # traffic bypasses the tunnel and uses the physical interface directly.
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
          # Cleanup is a handful of `ip route del`; never hold up shutdown.
          TimeoutStopSec = 10;
        };
      };
    };
  };
}
