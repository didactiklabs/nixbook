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
        - scx_lavd: sched_ext CPU scheduler built for interactivity and
          battery life (latency-critical tasks first, fewer cores awake)
        - powerManagement: general power management framework
        - powertop: power consumption analyser available in the system PATH

        Enable this on machines that are laptops (totoro, nishinoya, tanjiro).
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

      # sched_ext scheduler (kernel 6.12+) tuned for laptops: favours the
      # tasks the user is waiting on (input, compositor, audio, the focused
      # app) and packs background work onto fewer cores. Falls back to the
      # kernel's EEVDF scheduler if it stops. --autopower follows
      # power-profiles-daemon (performance / balanced / power-saver).
      scx = {
        enable = true;
        package = pkgs.scx.rustscheds;
        scheduler = "scx_lavd";
        extraArgs = [ "--autopower" ];
      };

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

    environment.systemPackages = [
      pkgs.powertop
    ];
  };
}
