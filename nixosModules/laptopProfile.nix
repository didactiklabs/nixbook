{
  config,
  options,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customNixOSModules.laptopProfile;

  # nixos-hardware's ASUS battery module (imported by its ASUS laptop
  # profiles, totoro's um6702 among them) writes its own limit
  # (hardware.asus.battery.chargeUpto, 100 by default) at boot and after
  # each resume, at the same time as battery-charge-limit: whichever ended
  # last won, and the limit chosen came back as 100 % after a reboot. This
  # module takes that over: its unit is turned off and a chargeUpto set to
  # something other than 100 is this module's default limit.
  asusBattery = options.hardware ? asus && options.hardware.asus ? battery;
  asusChargeUpto = if asusBattery then config.hardware.asus.battery.chargeUpto else 100;
  defaultLimit =
    if cfg.chargeLimit != null then
      toString cfg.chargeLimit
    else if asusChargeUpto != 100 then
      toString asusChargeUpto
    else
      "";

  # Writes the charge limit to every battery that has one. `restore`: the
  # limit last chosen at run time, else chargeLimit, else nothing. A number:
  # that limit, remembered for the next boots.
  chargeLimitScript = pkgs.writeShellScript "battery-charge-limit" ''
    set -u
    state=/var/lib/battery-charge-limit/limit
    arg=''${1:-restore}
    if [ "$arg" = restore ]; then
      limit=$(cat "$state" 2>/dev/null || true)
      [ -n "$limit" ] || limit=${defaultLimit}
      if [ -z "$limit" ]; then
        echo "no charge limit set"
        exit 0
      fi
    else
      limit=$arg
    fi
    case "$limit" in
      "" | *[!0-9]* | ????*)
        echo "not a percentage: $limit" >&2
        exit 1
        ;;
    esac
    limit=$((10#$limit))
    if [ "$limit" -lt 20 ] || [ "$limit" -gt 100 ]; then
      echo "a charge limit is between 20 and 100, not $limit" >&2
      exit 1
    fi
    set=0
    for file in /sys/class/power_supply/*/charge_control_end_threshold; do
      [ -w "$file" ] || continue
      if echo "$limit" > "$file"; then
        set=$((set + 1))
      fi
    done
    if [ "$set" -eq 0 ]; then
      echo "no battery here takes a charge limit (charge_control_end_threshold)" >&2
      # At boot that is how this computer is, not a failure.
      [ "$arg" = restore ] && exit 0
      exit 1
    fi
    if [ "$arg" != restore ]; then
      mkdir -p "''${state%/*}"
      echo "$limit" > "$state"
    fi
    echo "charging stops at $limit %"
  '';
  # Wi-Fi power save on battery, off on the charger, for every wireless
  # interface. Run when the charger is plugged in or out and each time
  # NetworkManager brings a connection up (it applies its own
  # wifi.powersave at every activation).
  wifiPowerSaveScript = pkgs.writeShellScript "wifi-power-save" ''
    set -u
    # On battery: there is a mains adapter and none is plugged in.
    mains=0
    online=0
    for supply in /sys/class/power_supply/*; do
      [ "$(cat "$supply/type" 2>/dev/null)" = Mains ] || continue
      mains=1
      [ "$(cat "$supply/online" 2>/dev/null)" = 1 ] && online=1
    done
    state=off
    [ "$mains" = 1 ] && [ "$online" = 0 ] && state=on
    for iface in /sys/class/net/*; do
      [ -d "$iface/wireless" ] || [ -L "$iface/phy80211" ] || continue
      name=''${iface##*/}
      if ${lib.getExe pkgs.iw} dev "$name" set power_save "$state"; then
        echo "$name: power save $state ($([ "$state" = on ] && echo on battery || echo on the charger))"
      fi
    done
    exit 0
  '';
  sleepTargets = [
    "suspend.target"
    "hibernate.target"
    "hybrid-sleep.target"
    "suspend-then-hibernate.target"
  ];
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
        - Wi-Fi power save on battery, off on the charger (wifiPowerSaveOnBattery)
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
      default = null;
      description = ''
        Power profile set at every boot, whatever was chosen before. null
        (the default): power-profiles-daemon keeps the last profile chosen
        (the bar's battery panel, the power button) across reboots and
        deploys. Set one to start each boot from it instead (performance
        left on by a single click cost totoro 23 W instead of 6-11 W at the
        same light load).
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
    chargeLimit = lib.mkOption {
      type = lib.types.nullOr (lib.types.ints.between 20 100);
      default = null;
      example = 80;
      description = ''
        Level (%) at which the battery stops charging, on laptops whose
        firmware has such a limit (`charge_control_end_threshold`: ASUS,
        Framework, ThinkPad…). A lithium battery kept at 100 % on the charger
        ages much faster than one kept at 80 %. null sets no limit.

        This is the limit a boot starts with until one is chosen at run time:
        `systemctl start battery-charge-limit@<percent>.service` (what
        nixbook-shell's battery panel does; no password for the person at the
        computer) applies another one and remembers it across reboots
        (/var/lib/battery-charge-limit/limit; delete it to come back to this
        option). Applied at boot and after each resume: some firmwares forget
        it. On ASUS laptops using nixos-hardware's battery module, its
        battery-charge-threshold unit is turned off (it wrote its own limit
        at the same time) and a hardware.asus.battery.chargeUpto other than
        100 is the default when this is null.
      '';
    };
    wifiPowerSaveOnBattery = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Wi-Fi power save on battery and off on the charger, switched as the
        charger is plugged in or out and each time NetworkManager brings a
        connection up (it applies its own `networking.networkmanager.wifi.powersave`
        at every activation, which this then corrects).

        Power save lets the radio doze between packets: less power, but late
        wake-ups that can make a steady stream (game streaming with Moonlight,
        a video call) stutter (seen on totoro's MediaTek MT7922). This keeps
        the radio awake while plugged in and lets it doze on battery. false:
        NetworkManager's setting alone, whatever the power source.
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
      ''
      # wifiPowerSaveOnBattery: the mains adapter only; on totoro the USB-C
      # controller's own supplies (type USB) announce a change several times
      # a second while charging.
      + lib.optionalString cfg.wifiPowerSaveOnBattery ''
        SUBSYSTEM=="power_supply", ACTION=="change", ATTR{type}=="Mains", RUN+="${config.systemd.package}/bin/systemctl --no-block start wifi-power-save.service"
      '';
    };
    systemd.services.power-profile-on-boot = lib.mkIf (cfg.powerProfileOnBoot != null) {
      description = "Start in the ${cfg.powerProfileOnBoot} power profile";
      after = [ "power-profiles-daemon.service" ];
      requires = [ "power-profiles-daemon.service" ];
      wantedBy = [ "multi-user.target" ];
      # At boot only: a oneshot that ended was started again by every system
      # switch (a deploy), which put the profile chosen since back to this
      # one; staying active and never restarted for a change, it isn't.
      restartIfChanged = false;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${lib.getExe' config.services.power-profiles-daemon.package "powerprofilesctl"} set ${cfg.powerProfileOnBoot}";
      };
    };

    # Not RemainAfterExit: the sleep targets start it again after each resume.
    systemd.services.battery-charge-limit = {
      description = "Battery charge limit";
      after = sleepTargets;
      wantedBy = [ "multi-user.target" ] ++ sleepTargets;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${chargeLimitScript} restore";
      };
    };
    # Ours alone (see asusBattery).
    systemd.services.battery-charge-threshold = lib.mkIf asusBattery {
      enable = lib.mkForce false;
    };
    systemd.services."battery-charge-limit@" = {
      description = "Stop charging the battery at %i %%";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${chargeLimitScript} %i";
      };
    };
    # The person at the computer changes the limit without a password (the
    # script takes a number from 20 to 100 and nothing else).
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units" &&
            /^battery-charge-limit@[0-9]{1,3}\.service$/.test(action.lookup("unit")) &&
            action.lookup("verb") == "start" &&
            subject.local && subject.active && subject.isInGroup("users")) {
          return polkit.Result.YES;
        }
      });
    '';

    # Not RemainAfterExit: the sleep targets start it again after each resume,
    # where the cores come back online.
    systemd.services.cpu-boost-off = lib.mkIf (!cfg.cpuBoost) ({
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
    });

    systemd.services.wifi-power-save = lib.mkIf cfg.wifiPowerSaveOnBattery {
      description = "Wi-Fi power save on battery, off on the charger";
      after = [ "NetworkManager.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = wifiPowerSaveScript;
      };
    };
    networking.networkmanager.dispatcherScripts = lib.mkIf cfg.wifiPowerSaveOnBattery [
      {
        type = "basic";
        source = pkgs.writeShellScript "wifi-power-save-dispatcher" ''
          [ "$2" = up ] || exit 0
          exec ${wifiPowerSaveScript}
        '';
      }
    ];

    powerManagement = lib.mkForce {
      enable = true;
    };

    environment.systemPackages = [
      pkgs.powertop
    ];
  };
}
