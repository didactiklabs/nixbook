{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customNixOSModules.laptopProfile;
in
{
  options.customNixOSModules.laptopProfile = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        whether to enable laptopProfile globally or not
      '';
    };
  };
  config = lib.mkIf cfg.enable {
    services = {
      power-profiles-daemon.enable = true;
      fwupd.enable = true;
      thermald.enable = true;
    };
    hardware = {
      enableAllFirmware = true;
      enableRedistributableFirmware = true;
      cpu.intel.updateMicrocode = true;
    };
    powerManagement = lib.mkForce {
      enable = true;
    };
    environment.systemPackages = [
      pkgs.powertop
    ];
  };
}
