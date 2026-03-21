{
  config,
  lib,
  ...
}:
let
  cfg = config.customNixOSModules;
in
{
  options.customNixOSModules.firewall = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable the NixOS stateful firewall (nftables/iptables).

        Configures a deny-by-default inbound policy: all incoming connections are
        silently dropped (rejectPackets = false) unless explicitly listed in
        allowedTCPPorts or allowedUDPPorts.  Refused connection attempts are
        logged to the journal (logRefusedConnections = true).

        Dropping rather than rejecting packets avoids leaking network topology
        to external scanners.  Outbound traffic is unrestricted.

        Disabled by default — enable per-machine in profiles/{hostname}/configuration.nix
        and set the port lists as needed.
      '';
    };
    allowedTCPPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ ];
      description = ''
        List of TCP port numbers to allow inbound through the firewall.
        Example: [ 22 80 443 ]
      '';
    };
    allowedUDPPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ ];
      description = ''
        List of UDP port numbers to allow inbound through the firewall.
        Example: [ 51820 ] # WireGuard
      '';
    };
  };

  config = lib.mkIf cfg.firewall.enable {
    networking.firewall = {
      enable = true;
      inherit (cfg.firewall) allowedTCPPorts;
      inherit (cfg.firewall) allowedUDPPorts;
      # Drop rather than reject to avoid leaking topology info
      rejectPackets = false;
      logRefusedConnections = true;
    };
  };
}
