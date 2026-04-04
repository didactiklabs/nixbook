{
  config,
  pkgs,
  lib,
  sources,
  ...
}:
let
  cfg = config.customNixOSModules;
in
{
  options.customNixOSModules.core = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to enable the core NixOS module.

        This is the foundational system module that configures:
        - Boot: systemd-boot UEFI loader, plymouth splash screen, latest kernel,
          LVM support, LUKS dm-crypt modules, keyboard backlight on initrd, IOMMU
        - Kernel hardening: sysctl security settings (restrict BPF, perf events,
          ICMP redirects, source routing, suid dumps, etc.)
        - Locale: Europe/Paris timezone, en_US locale with fr_FR LC_ settings,
          French keyboard layout
        - Audio: PipeWire with ALSA and PulseAudio compatibility (PulseAudio disabled)
        - Hardware: firmware, Intel/AMD CPU microcode, Bluetooth (bluez), uinput
        - Security: rtkit, polkit, U2F PAM (login + sudo), passwordless sudo for wheel
        - XDG portals: wlr portal enabled for Wayland screen sharing
        - Nix daemon: lix package, weekly GC (7d retention), store optimisation at 03:45,
          nix-command + flakes features, custom S3 binary cache, OOM-managed nix-daemon slice
        - Display: xserver disabled (Wayland-only), fonts dir enabled
        - Env: NIXOS_OZONE_WL=1, NIXPKGS_ALLOW_UNFREE=1
        - System state version: 24.05
      '';
    };
  };

  config = lib.mkIf cfg.core.enable {
    nixpkgs = {
      config = {
        allowUnfree = true;
        permittedInsecurePackages = [
          "qtwebengine-5.15.19"
        ];
      };
      overlays = [
        (
          final: prev:
          let
            lixStable = prev.lixPackageSets.stable;
          in
          {
            inherit (lixStable)
              nixpkgs-review
              nix-eval-jobs
              nix-fast-build
              ;
          }
        )
      ];
    };

    boot = {
      initrd = {
        availableKernelModules = [
          "nvme"
          "xhci_pci"
          "ahci"
          "usb_storage"
          "sd_mod"
          "ata_piix"
          "dm_crypt"
        ];
        services.lvm.enable = true;
        postDeviceCommands = ''
          for KBD_BACKLIGHT_PATH in /sys/class/leds/*::kbd_backlight/brightness; do
            if [ -f "$KBD_BACKLIGHT_PATH" ]; then
              echo 2 > "$KBD_BACKLIGHT_PATH"
            fi
          done
        '';
      };
      # Bootloader.
      kernelModules = [
        "uinput"
        "usbhid"
      ];
      kernel = {
        sysctl = {
          # Restricts /dev/kmsg and dmesg(1) to root.
          # Defends against: information leakage of kernel addresses, loaded modules,
          # hardware layout — useful recon data for local privilege escalation.
          # Side effects: non-root users cannot read kernel boot messages; tools like
          # `journalctl -k` still work for wheel users via systemd.
          "kernel.dmesg_restrict" = 1;

          # Hides kernel symbol addresses (/proc/kallsyms, /proc/modules) from
          # non-root even when they have CAP_SYSLOG.
          # Defends against: KASLR bypass — knowing kernel symbol addresses is a
          # prerequisite for most kernel exploit chains.
          # Side effects: none for normal use; kernel developers/debuggers need root.
          "kernel.kptr_restrict" = 2;

          # Caps the maximum PID to 65536 (default on most distros already).
          # Defends against: PID wrap-around attacks where a process waits for a
          # privileged PID to be recycled and hijacks it.
          # Side effects: limits to ~65k concurrent processes — irrelevant on a laptop.
          "kernel.pid_max" = 65536;

          # Limits the CPU time the perf subsystem may consume to 1 %.
          # Defends against: perf-based side-channel attacks (e.g. Spectre variants
          # that abuse hardware performance counters) and DoS via perf event floods.
          # Side effects: profiling with `perf` will be throttled; use as root or
          # temporarily raise if doing serious performance work.
          "kernel.perf_cpu_time_max_percent" = 1;
          "kernel.perf_event_max_sample_rate" = 1;

          # Restricts access to perf_event_open(2) to root (paranoid = 2).
          # Defends against: hardware PMU side-channels (Spectre-v1/v2, Meltdown
          # variants) and covert channels between processes.
          # Side effects: unprivileged `perf stat/record` will fail; needs root or
          # a temporary sysctl override for profiling sessions.
          "kernel.perf_event_paranoid" = 2;

          # Triggers a kernel panic on any oops instead of attempting to continue.
          # Defends against: exploits that deliberately trigger oopses to reach a
          # partially corrupted but exploitable kernel state.
          # Side effects: a buggy driver oops will hard-reboot the machine instead
          # of just killing the offending process. Rare in practice with stable kernels.
          "kernel.panic_on_oops" = 1;

          # Hardens the BPF JIT compiler against JIT spraying attacks.
          # Value 2 = randomise JIT image addresses AND disable unprivileged JIT.
          "net.core.bpf_jit_harden" = 2;

          # Disables acceptance of ICMP redirect messages on all interfaces.
          "net.ipv4.conf.all.accept_redirects" = 0;
          "net.ipv4.conf.default.accept_redirects" = 0;

          # Disables "secure" ICMP redirects (from known gateways only).
          "net.ipv4.conf.all.secure_redirects" = 0;
          "net.ipv4.conf.default.secure_redirects" = 0;

          # Disables shared-media assumption on interfaces.
          "net.ipv4.conf.all.shared_media" = 0;
          "net.ipv4.conf.default.shared_media" = 0;

          # Disables IP source routing (loose and strict).
          "net.ipv4.conf.all.accept_source_route" = 0;
          "net.ipv4.conf.default.accept_source_route" = 0;

          # Enables ARP filtering: only reply to ARP requests for addresses
          # assigned to the incoming interface.
          "net.ipv4.conf.all.arp_filter" = 1;

          # Restricts ARP replies to requests targeting the exact address of
          # the receiving interface (mode 1).
          "net.ipv4.conf.all.arp_ignore" = 1;

          # Enables reverse-path filtering (strict mode).
          "net.ipv4.conf.default.rp_filter" = 1;
          "net.ipv4.conf.all.rp_filter" = 1;

          # Prevents the kernel from sending ICMP redirects to other hosts.
          "net.ipv4.conf.default.send_redirects" = 0;
          "net.ipv4.conf.all.send_redirects" = 0;

          # Silently discards bogus ICMP error responses (RFC 1122).
          "net.ipv4.icmp_ignore_bogus_error_responses" = 1;

          # Protects against TCP TIME-WAIT assassination (RFC 1337).
          "net.ipv4.tcp_rfc1337" = 1;

          # Prevents suid/sgid processes from dumping core files.
          "fs.suid_dumpable" = 0;

          # Restricts creation of FIFOs in world-writable sticky directories.
          "fs.protected_fifos" = 2;

          # Restricts creation of regular files in world-writable sticky directories.
          "fs.protected_regular" = 2;

          # Prevents creating hard links to files you do not own.
          "fs.protected_hardlinks" = 1;

          # Prevents following symlinks in world-writable sticky directories
          # unless the symlink owner matches the follower or directory owner.
          "fs.protected_symlinks" = 1;

          # Restricts ptrace(2) to processes in a parent-child relationship.
          "kernel.yama.ptrace_scope" = 1;

          # IPv6: disables ICMP redirect acceptance.
          "net.ipv6.conf.all.accept_redirects" = 0;
          "net.ipv6.conf.default.accept_redirects" = 0;

          # IPv6: disables source routing.
          "net.ipv6.conf.all.accept_source_route" = 0;
          "net.ipv6.conf.default.accept_source_route" = 0;
        };
      };
      tmp.cleanOnBoot = true;
      kernelParams = [
        "intel_iommu=on"
        "iommu=pt"
        "amdgpu.dcdebugmask=0x10"
        "quiet"
        "splash"
      ];
      kernelPackages = pkgs.linuxPackages_latest;
      plymouth.enable = true;
      loader = {
        systemd-boot = {
          enable = true;
          configurationLimit = 10;
        };

        efi.canTouchEfiVariables = true;
      };
      tmp = {
        useTmpfs = false;
        tmpfsSize = "30%";
      };
    };

    # Set your time zone.
    time.timeZone = "Europe/Paris";
    services.chrony.enable = true;

    # Select internationalisation properties.
    i18n.defaultLocale = "en_US.UTF-8";
    i18n.extraLocaleSettings = {
      LC_ADDRESS = "fr_FR.UTF-8";
      LC_IDENTIFICATION = "fr_FR.UTF-8";
      LC_MEASUREMENT = "fr_FR.UTF-8";
      LC_MONETARY = "fr_FR.UTF-8";
      LC_NAME = "fr_FR.UTF-8";
      LC_NUMERIC = "fr_FR.UTF-8";
      LC_PAPER = "fr_FR.UTF-8";
      LC_TELEPHONE = "fr_FR.UTF-8";
      LC_TIME = "fr_FR.UTF-8";
      LC_ALL = "C.UTF-8";
    };
    console.keyMap = "fr";
    services = {
      fprintd.enable = true;
      accounts-daemon.enable = true;
      fwupd.enable = true;
      upower.enable = true;
      pcscd.enable = true; # yubikey smart card mode
      pipewire = {
        enable = true;
        alsa.enable = true;
        alsa.support32Bit = true;
        pulse.enable = true;
      };
      resolved.enable = true;
      xserver = {
        enable = false;
        xkb.layout = "fr";
        xkb.variant = "oss_latin9";
      };

      pulseaudio.enable = false;
    };

    xdg = {
      portal = {
        enable = true;
        wlr.enable = true;
      };
    };

    hardware = {
      enableAllFirmware = true;
      enableRedistributableFirmware = true;
      cpu.intel.updateMicrocode = true;
      cpu.amd.updateMicrocode = true;
      bluetooth = {
        enable = true;
        powerOnBoot = false;
        package = pkgs.bluez;
      };
      uinput.enable = true;
    };

    security = {
      rtkit.enable = true;
      polkit = {
        enable = true;
        extraConfig = ''
          polkit.addRule(function(action, subject) {
            if (action.id == "net.reactivated.fprint.device.enroll" &&
                subject.isInGroup("wheel")) {
              return polkit.Result.YES;
            }
          });
          polkit.addRule(function(action, subject) {
            if (action.id == "org.freedesktop.systemd1.manage-units" &&
                action.lookup("unit") == "nixos-upgrade-manual.service" &&
                subject.isInGroup("wheel")) {
              return polkit.Result.YES;
            }
          });
          polkit.addRule(function(action, subject) {
            if (action.id == "org.freedesktop.systemd1.manage-units" &&
                (action.lookup("unit") == "clamav-daemon.service" ||
                 action.lookup("unit") == "clamav-freshclam.service") &&
                subject.isInGroup("wheel")) {
              return polkit.Result.YES;
            }
          });
        '';
      };
      sudo.wheelNeedsPassword = lib.mkDefault false;
      pam = {
        services = {
          login.u2fAuth = true;
          sudo.u2fAuth = true;
        };
        u2f.enable = true;
      };
    };

    nix = {
      # Pin <nixpkgs> (used by nix-shell -p) to the npins-pinned revision
      nixPath = [
        "nixpkgs=${sources.nixpkgs}"
      ];
      # Pin the flake registry (used by nix shell nixpkgs#) to the same revision
      registry.nixpkgs = {
        exact = true;
        to = {
          type = "path";
          path = "${sources.nixpkgs}";
        };
      };
      package = pkgs.lixPackageSets.stable.lix;
      gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 7d";
      };
      optimise = {
        automatic = true;
        dates = [ "03:45" ];
      };
      settings = {
        trusted-users = [
          "root"
          "@wheel"
        ];
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        substituters = [ "https://s3.didactiklabs.io/nix-cache" ];
        trusted-public-keys = [
          "didactiklabs-nixcache:PxLKN0+ZkP07M8g8/B6xbP6A4MYpqQg6LH7V3muiy/0="
        ];
      };
      extraOptions = ''
        fallback = true
        min-free = ${toString (10240 * 1024 * 1024)}
        max-free = ${toString (10240 * 1024 * 1024)}
      '';
    };

    # zram swap (compressed RAM) with disk fallback
    zramSwap = {
      enable = true;
      algorithm = "zstd";
      memoryPercent = 50;
    };
    swapDevices = [
      {
        device = "/swapfile";
        size = 8 * 1024; # 8GB fallback in MB
        priority = 0; # lower priority than zram
      }
    ];

    networking.firewall.enable = lib.mkDefault false;
    networking.networkmanager.enable = true;

    systemd = {
      # Create a separate slice for nix-daemon that is
      # memory-managed by the userspace systemd-oomd killer
      slices."nix-daemon".sliceConfig = {
        ManagedOOMMemoryPressure = "kill";
        ManagedOOMMemoryPressureLimit = "50%";
      };
      services = {
        "nix-daemon".serviceConfig.Slice = "nix-daemon.slice";
        # If a kernel-level OOM event does occur anyway,
        # strongly prefer killing nix-daemon child processes
        "nix-daemon".serviceConfig.OOMScoreAdjust = 1000;
        # Manual NixOS upgrade service triggered by the DMS nixosUpdate bar widget
      };
    };

    system.stateVersion = "24.05";

    environment.variables = {
      NIXOS_OZONE_WL = "1";
      NIXPKGS_ALLOW_UNFREE = 1;
    };

    fonts.fontDir.enable = true;
  };
}
