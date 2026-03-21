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
        Whether to enable laptop-specific power and display optimisations.

        Configures:
        - logind lid-switch behaviour: suspend on close, lock when on external power,
          ignore when docked
        - power-profiles-daemon: dynamic CPU frequency scaling (performance / balanced /
          power-saver profiles, switchable via e.g. the DMS control centre)
        - thermald: Intel thermal management daemon to prevent CPU throttling
        - powerManagement: general power management framework
        - powertop: power consumption analyser available in the system PATH

        Enable this on machines that are laptops (totoro, nishinoya).
        Leave disabled on desktop/server machines (anya).
      '';
    };
  };
  config = lib.mkIf cfg.enable {
    services.logind.settings.Login = {
      HandleLidSwitch = "suspend";
      HandleLidSwitchExternalPower = "lock";
      HandleLidSwitchDocked = "ignore";
    };
    services = {
      power-profiles-daemon.enable = true;
      thermald.enable = true;
    };
    powerManagement = lib.mkForce {
      enable = true;
    };
    environment.systemPackages = [
      pkgs.powertop
    ];
  };
}
