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
        - gnome.simple-scan: GTK scanning GUI

        Enable on machines that have a physical printer or scanner attached,
        or that need to discover network printers via mDNS.
      '';
    };
  };
  config = lib.mkIf cfg.printTools.enable {
    environment = {
      systemPackages = with pkgs; [ gnome.simple-scan ];
    };
    services = {
      ipp-usb.enable = true;
      avahi.enable = true;
      avahi.nssmdns4 = true;
      printing.enable = true;
    };
    hardware = {
      sane = {
        enable = true;
        extraBackends = [ pkgs.sane-airscan ];
      };
    };
  };
}
