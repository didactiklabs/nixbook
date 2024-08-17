{ config, pkgs, lib, ... }:
let cfg = config.customNixOSModules;
in {
  options.customNixOSModules.printTools = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        whether to enable printTools globally or not.
      '';
    };
  };
  config = lib.mkIf cfg.printTools.enable {
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
