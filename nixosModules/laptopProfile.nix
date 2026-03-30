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
    services = {
      logind.settings.Login = {
        HandleLidSwitch = "suspend";
        HandleLidSwitchExternalPower = "lock";
        HandleLidSwitchDocked = "ignore";
      };

      power-profiles-daemon.enable = true;
      thermald.enable = true;

      # Set SATA link power management to the most aggressive power-saving policy
      # that still allows DIPM (Device Initiated Power Management) — safe on NVMe+SATA.
      # "med_power_with_dipm" is the sweet spot: real savings without the latency
      # spikes of "min_power" that can cause filesystem stalls.
      udev.extraRules = ''
        ACTION=="add", SUBSYSTEM=="scsi_host", KERNEL=="host*", ATTR{link_power_management_policy}="med_power_with_dipm"
      '';
    };
    powerManagement = lib.mkForce {
      enable = true;
    };
    # nvme.noacpi=1: let the NVMe driver manage the drive's power state directly
    # instead of deferring to ACPI, which is broken on many laptops and prevents
    # the drive from entering deep idle (PS3/PS4) during suspend.
    # Note: mem_sleep_default=deep removed — modern AMD laptops (ZenBook UM6702,
    # Framework 13 AMD) don't support S3 properly and freeze on resume. s2idle
    # is the default and works correctly with these firmwares.
    boot.kernelParams = [
      "nvme.noacpi=1"
    ];
    environment.systemPackages = [
      pkgs.powertop
    ];
  };
}
