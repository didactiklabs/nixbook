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
        Whether to enable the firewall module.
        Enables the NixOS firewall with a deny-by-default policy,
        blocking all inbound connections unless explicitly allowed.
      '';
    };
    allowedTCPPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ ];
      description = "List of TCP ports to allow inbound.";
    };
    allowedUDPPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ ];
      description = "List of UDP ports to allow inbound.";
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
