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
        pkgs.tailscale
      ]
    }:$PATH"

    # Track throw routes we've added so we can clean them up on exit.
    ADDED_ROUTES=""

    # Remove all throw routes we injected into table 52.
    cleanup_routes() {
      echo "Cleaning up throw routes from table 52..."
      for subnet in $ADDED_ROUTES; do
        if ip route show table 52 "$subnet" 2>/dev/null | grep -q "^throw"; then
          echo "Removing throw route for $subnet from table 52"
          ip route del throw "$subnet" table 52 2>/dev/null || true
        fi
      done
      ADDED_ROUTES=""
    }

    # Clean up throw routes when the service stops (e.g. tailscaled goes
    # down and systemd tears us down via bindsTo).
    trap cleanup_routes EXIT TERM INT

    # Collect all IPv4 subnets directly connected to physical interfaces,
    # excluding VPN tunnels (tailscale0, wt*) and loopback.
    get_local_subnets() {
      ip -4 route show proto kernel \
        | grep -vE 'dev (tailscale0|wt[^ ]*|lo) ' \
        | awk '{print $1}' \
        | grep '/' || true
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
          # Track for cleanup
          case " $ADDED_ROUTES " in
            *" $subnet "*) ;;  # already tracked
            *) ADDED_ROUTES="$ADDED_ROUTES $subnet" ;;
          esac
        fi
      done <<< "$local_subnets"
    }

    # Wait for Tailscale to be up before doing anything
    while ! tailscale status >/dev/null 2>&1; do
      echo "Waiting for Tailscale to come up..."
      sleep 5
    done

    # Run once at startup
    fix_routes

    # Re-check whenever a route changes on tailscale0 (e.g. Tailscale
    # re-adds its subnet route after we threw it).
    ip monitor route | while IFS= read -r line; do
      case "$line" in
        *tailscale0*) fix_routes ;;
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
        };
      };
    };
  };
}
