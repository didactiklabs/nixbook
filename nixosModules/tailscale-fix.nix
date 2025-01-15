{ pkgs, ... }:
let
  tailscale-switch = pkgs.writeShellScriptBin "tswitch" ''
    # Get the list of available Tailnets
    tailnet_list=$(tailscale switch --list | tail -n +2 2>/dev/null)

    # Use fzf to select a Tailnet
    selected_tailnet=$(echo "$tailnet_list" | fzf --prompt="Select a Tailnet> ")

    if [[ -z "$selected_tailnet" ]]; then
      echo "No Tailnet selected. Exiting."
      exit 1
    fi

    tailnet_name=$(echo "$selected_tailnet" | awk '{gsub("\\*", "", $3); print $3}')
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
  environment = {
    systemPackages = [
      tailscale-switch
    ];
  };
  systemd = {
    services.tailscale-fix-routes = {
      enable = true;
      path = [
        pkgs.iproute2
        pkgs.busybox
      ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${tailscale-fix-routes}/bin/tailscale-fix-routes";
        Restart = "always";
      };
    };
  };
}
