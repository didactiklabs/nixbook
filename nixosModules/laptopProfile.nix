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
          (Intel CPUs only: the hardware configuration loads kvm-intel)
        - scx_lavd: sched_ext CPU scheduler built for interactivity and
          battery life (latency-critical tasks first, fewer cores awake)
        - powerManagement: general power management framework
        - powertop: power consumption analyser available in the system PATH

        Enable this on machines that are laptops (totoro, nishinoya, tanjiro).
        Leave disabled on desktop/server machines (anya).
      '';
    };
    powerProfileOnBoot = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "power-saver"
          "balanced"
          "performance"
        ]
      );
      default = "balanced";
      description = ''
        Power profile set at every boot. power-profiles-daemon otherwise
        keeps the last one chosen across reboots, so a single click on the
        bar's power button left a laptop in performance (on totoro: 23 W
        instead of 6-11 W at the same light load, ~10 °C hotter) until
        changed back. null keeps the saved profile.
      '';
    };
    cpuBoost = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether the CPU may run above its nominal frequency (turbo, Core
        Performance Boost). false caps every core at the nominal frequency
        its firmware reports (ACPI CPPC `nominal_freq`; on totoro 2.7 GHz
        instead of 4.77 GHz): cooler, and where the CPU and an integrated GPU
        share one power budget more of it is left to the GPU in games, for
        slower single-thread work everywhere.

        The cap is each core's `scaling_max_freq`, not the global
        `cpufreq/boost` switch: with that one off the kernel refuses every
        write to the per-core `boost` files, which power-profiles-daemon
        writes at each profile change, so the profile could no longer be
        changed ("Failed to activate CPU driver 'amd_pstate'").
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
      # Intel only: on AMD it exits at every boot ("Unsupported cpu model or
      # platform"). The generated hardware configuration loads kvm-intel or
      # kvm-amd, the one sure sign of the CPU vendor here.
      thermald.enable = lib.elem "kvm-intel" config.boot.kernelModules;

      # sched_ext scheduler (kernel 6.12+) tuned for laptops: favours the
      # tasks the user is waiting on (input, compositor, audio, the focused
      # app) and packs background work onto fewer cores. Falls back to the
      # kernel's EEVDF scheduler if it stops. --autopower follows
      # power-profiles-daemon (performance / balanced / power-saver).
      # Run by scx_loader (nixpkgs replaced `services.scx` with it): it starts
      # `default_sched` in `default_mode` with that mode's flags from
      # /etc/scx_loader.toml; a mode left out keeps scx_loader's own flags.
      scx-loader = {
        enable = true;
        schedsPackages = [ pkgs.scx.rustscheds ];
        config = {
          default_sched = "scx_lavd";
          default_mode = "Auto";
          scheds.scx_lavd.auto_mode = [ "--autopower" ];
        };
      };

      # Set SATA link power management to the most aggressive power-saving policy
      # that still allows DIPM (Device Initiated Power Management) — safe on NVMe+SATA.
      # "med_power_with_dipm" is the sweet spot: real savings without the latency
      # spikes of "min_power" that can cause filesystem stalls. The TEST skips
      # hosts without the attribute (USB storage), which udev logged every boot.
      udev.extraRules = ''
        ACTION=="add", SUBSYSTEM=="scsi_host", KERNEL=="host*", TEST=="link_power_management_policy", ATTR{link_power_management_policy}="med_power_with_dipm"
      '';
    };
    systemd.services.power-profile-on-boot = lib.mkIf (cfg.powerProfileOnBoot != null) {
      description = "Start in the ${cfg.powerProfileOnBoot} power profile";
      after = [ "power-profiles-daemon.service" ];
      requires = [ "power-profiles-daemon.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe' config.services.power-profiles-daemon.package "powerprofilesctl"} set ${cfg.powerProfileOnBoot}";
      };
    };

    # Not RemainAfterExit: the sleep targets start it again after each resume,
    # where the cores come back online.
    systemd.services.cpu-boost-off = lib.mkIf (!cfg.cpuBoost) (
      let
        sleepTargets = [
          "suspend.target"
          "hibernate.target"
          "hybrid-sleep.target"
          "suspend-then-hibernate.target"
        ];
      in
      {
        description = "Cap the CPU at its nominal frequency (no boost)";
        after = sleepTargets;
        wantedBy = [ "multi-user.target" ] ++ sleepTargets;
        serviceConfig.Type = "oneshot";
        script = ''
          capped=0
          for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
            nominal=$(cat "$cpu/acpi_cppc/nominal_freq" 2>/dev/null || echo 0)
            if [ "$nominal" -gt 0 ] && [ -w "$cpu/cpufreq/scaling_max_freq" ]; then
              echo $((nominal * 1000)) > "$cpu/cpufreq/scaling_max_freq"
              capped=$((capped + 1))
            fi
          done
          if [ "$capped" -eq 0 ]; then
            echo "no core reports a nominal frequency (acpi_cppc/nominal_freq): boost left on" >&2
            exit 1
          fi
          echo "$capped cores capped at their nominal frequency"
        '';
      }
    );

    powerManagement = lib.mkForce {
      enable = true;
    };

    environment.systemPackages = [
      pkgs.powertop
    ];
  };
}
