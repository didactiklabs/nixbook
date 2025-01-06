{ pkgs, ... }:
let
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
