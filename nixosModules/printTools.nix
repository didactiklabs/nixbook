{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customNixOSModules;
in
{
  options.customNixOSModules.printTools = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable printing and scanning support.

        Configures a full CUPS + SANE stack for local and network printers/scanners:
        - CUPS printing daemon (services.printing)
        - ipp-usb: IPP-over-USB daemon for driverless USB printer/scanner access
        - Avahi mDNS/DNS-SD (with nssmdns4) for auto-discovery of network printers
        - SANE scanner framework with the airscan backend for WiFi/IPP scanners
        - simple-scan: GTK scanning GUI

        cups-browsed is explicitly disabled: modern CUPS does driverless /
        IPP-Everywhere discovery natively via Avahi/DNS-SD, and browsed's legacy
        "implicitclass://" auto-queues silently drop jobs when they can't resolve
        a destination host. Add discovered driverless printers directly through
        the CUPS web UI (http://localhost:631) instead.

        Enable on machines that have a physical printer or scanner attached,
        or that need to discover network printers via mDNS.
      '';
    };
  };
  config = lib.mkIf cfg.printTools.enable {
    environment = {
      systemPackages = with pkgs; [ simple-scan ];
    };
    services = {
      ipp-usb.enable = true;
      avahi.enable = true;
      avahi.nssmdns4 = true;
      printing.enable = true;
      # Disable cups-browsed. It creates legacy "implicitclass://" auto-queues
      # from mDNS discovery that silently swallow print jobs when it can't
      # resolve a destination host ("No suitable destination host found by
      # cups-browsed, retrying later"). Modern CUPS (2.4+) does driverless /
      # IPP-Everywhere discovery natively via Avahi/DNS-SD without browsed, so
      # this daemon is redundant and only a source of flaky, half-broken
      # queues. Keeping it off forces a clean rebuild to stop and remove it.
      printing.browsed.enable = false;
    };
    hardware = {
      sane = {
        enable = true;
        extraBackends = [ pkgs.sane-airscan ];
      };
    };
  };
}
