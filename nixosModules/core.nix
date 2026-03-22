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
          # Defends against: JIT spraying — an attacker floods the JIT cache with
          # shellcode-containing BPF programs to create predictable ROP gadgets.
          # Side effects: none for normal use; only affects eBPF program compilation.
          "net.core.bpf_jit_harden" = 2;

          # Disables acceptance of ICMP redirect messages on all interfaces.
          # Defends against: ICMP redirect attacks where a rogue router on the local
          # segment (e.g. coffee-shop WiFi) poisons your routing table to MITM traffic.
          # Side effects: none — redirects are a legacy mechanism not needed on modern
          # point-to-point or NATed networks.
          "net.ipv4.conf.all.accept_redirects" = 0;
          "net.ipv4.conf.default.accept_redirects" = 0;

          # Disables "secure" ICMP redirects (from known gateways only).
          # Defends against: same redirect poisoning attack as above; the "secure"
          # variant is still exploitable if the attacker controls a listed gateway.
          # Side effects: none.
          "net.ipv4.conf.all.secure_redirects" = 0;
          "net.ipv4.conf.default.secure_redirects" = 0;

          # Disables shared-media assumption on interfaces.
          # Defends against: ARP cache poisoning on non-broadcast links by preventing
          # the kernel from assuming all peers share the same L2 segment.
          # Side effects: none on typical Ethernet/WiFi setups.
          "net.ipv4.conf.all.shared_media" = 0;
          "net.ipv4.conf.default.shared_media" = 0;

          # Disables IP source routing (loose and strict).
          # Defends against: source-routed packets that force traffic through an
          # attacker-controlled path, bypassing firewalls and enabling MITM.
          # Side effects: none — source routing is unused on modern networks.
          "net.ipv4.conf.all.accept_source_route" = 0;
          "net.ipv4.conf.default.accept_source_route" = 0;

          # Enables ARP filtering: only reply to ARP requests for addresses assigned
          # to the incoming interface.
          # Defends against: ARP spoofing and IP address impersonation on multi-homed
          # hosts (e.g. VPN + WiFi active simultaneously).
          # Side effects: none on single-interface setups; may affect exotic
          # multi-homed routing configurations.
          "net.ipv4.conf.all.arp_filter" = 1;

          # Restricts ARP replies to requests targeting the exact address of the
          # receiving interface (mode 1).
          # Defends against: ARP-based host enumeration and IP takeover on shared
          # networks — attackers cannot probe which IPs a multi-homed host owns.
          # Side effects: none on typical setups; can break certain load-balancing
          # configurations that rely on gratuitous ARP.
          "net.ipv4.conf.all.arp_ignore" = 1;

          # Enables reverse-path filtering: drops packets whose source address is
          # not reachable via the interface they arrived on.
          # Defends against: IP spoofing and asymmetric routing exploits; packets
          # with forged source IPs are silently dropped.
          # Side effects: can break asymmetric routing setups (e.g. policy routing,
          # some VPN split-tunnel configs). Set to 2 (loose) if that's a problem.
          "net.ipv4.conf.default.rp_filter" = 1;
          "net.ipv4.conf.all.rp_filter" = 1;

          # Prevents the kernel from sending ICMP redirects to other hosts.
          # Defends against: this host being abused as a redirect source in a
          # multi-stage MITM attack; also avoids leaking network topology.
          # Side effects: none — only routers need to send redirects.
          "net.ipv4.conf.default.send_redirects" = 0;
          "net.ipv4.conf.all.send_redirects" = 0;

          # Silently discards ICMP error responses that violate RFC 1122
          # (e.g. broadcast/multicast source addresses).
          # Defends against: ICMP-based network mapping and some DoS amplification
          # techniques that abuse malformed error messages.
          # Side effects: none.
          "net.ipv4.icmp_ignore_bogus_error_responses" = 1;

          # Protects against TCP TIME-WAIT assassination (RFC 1337).
          # Defends against: an attacker sending forged RST/SYN packets to tear down
          # or hijack connections in TIME-WAIT state.
          # Side effects: none.
          "net.ipv4.tcp_rfc1337" = 1;

          # Prevents suid/sgid processes from dumping core files.
          # Defends against: core dumps of privileged processes leaking secrets
          # (private keys, passwords, tokens) into world-readable files.
          # Side effects: you cannot post-mortem debug a crashed suid binary without
          # temporarily setting this to 1 as root.
          "fs.suid_dumpable" = 0;

          # Restricts creation of FIFOs in world-writable sticky directories
          # (e.g. /tmp) to the directory owner or the FIFO owner only.
          # Defends against: FIFO-based privilege escalation where an attacker
          # pre-creates a named pipe in /tmp waiting for a privileged process to
          # open it (classic tmp-race attacks).
          # Side effects: none for normal use.
          "fs.protected_fifos" = 2;

          # Same restriction as protected_fifos but for regular files.
          # Defends against: an attacker pre-creating a file in /tmp with a name a
          # privileged process will later open for writing (e.g. log files, lock files).
          # Side effects: none for normal use.
          "fs.protected_regular" = 2;

          # Prevents creating hard links to files you do not own.
          # Defends against: hardlink-based privilege escalation where an attacker
          # creates a hard link to a suid binary inside a writable directory and waits
          # for a race condition to exploit it.
          # Side effects: none — legitimate hard links are always to files you own.
          "fs.protected_hardlinks" = 1;

          # Prevents following symlinks in world-writable sticky directories unless
          # the symlink owner matches the follower or the directory owner.
          # Defends against: symlink-based TOCTOU attacks in /tmp (e.g. a process
          # checks a path then a symlink is swapped in before the privileged open).
          # Side effects: none for normal use; exotic setups that rely on cross-owner
          # symlinks in /tmp may break.
          "fs.protected_symlinks" = 1;

          # Restricts ptrace(2) to processes in a parent-child relationship (scope 1).
          # Defends against: a compromised or malicious process attaching a debugger
          # to your browser, password manager, or SSH agent to extract secrets from
          # their memory without any privilege escalation.
          # Side effects: `strace`/`gdb` on an already-running process requires root
          # or that the target process is a direct child. Launching `gdb ./program`
          # normally is unaffected.
          "kernel.yama.ptrace_scope" = 1;

          # IPv6: disables ICMP redirect acceptance (mirrors IPv4 settings above).
          # Defends against: the same redirect-poisoning attack on IPv6 networks —
          # particularly relevant on dual-stack WiFi (hotels, conferences).
          # Side effects: none.
          "net.ipv6.conf.all.accept_redirects" = 0;
          "net.ipv6.conf.default.accept_redirects" = 0;

          # IPv6: disables source routing (mirrors IPv4 settings above).
          # Defends against: source-routed IPv6 packets forcing traffic through an
          # attacker-controlled path.
          # Side effects: none.
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

    # Swap configuration
    swapDevices = [
      {
        device = "/swapfile";
        size = 16 * 1024; # 16GB in MB
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
      services."nix-daemon".serviceConfig.Slice = "nix-daemon.slice";
      # If a kernel-level OOM event does occur anyway,
      # strongly prefer killing nix-daemon child processes
      services."nix-daemon".serviceConfig.OOMScoreAdjust = 1000;
    };

    system.stateVersion = "24.05";

    environment.variables = {
      NIXOS_OZONE_WL = "1";
      NIXPKGS_ALLOW_UNFREE = 1;
    };

    fonts.fontDir.enable = true;
  };
}
