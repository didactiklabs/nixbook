{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customNixOSModules.gamingConfig;
  # NOTE: Must use direct import here instead of the `sources` module arg,
  # because this is used in `imports` which cannot depend on `config`/_module.args.
  sources = import ../npins;
  # Upstream (nix-proton-cachyos) fetches the immutable GitHub release tarball
  # (proton-cachyos-<ver>-slr-<arch>.tar.xz) with the hash tracked in its own
  # versions.json, and installs the tool to
  #   $out/share/steam/compatibilitytools.d/proton-cachyos-slr
  # with a single `out` output.
  #
  # NixOS's `programs.steam.extraCompatPackages` however consumes tools via
  # `lib.makeSearchPathOutput "steamcompattool"`, so each package must expose a
  # dedicated `steamcompattool` output pointing straight at the tool directory
  # (the proton-ge-bin pattern). We therefore wrap the upstream package to add
  # that output.
  #
  # NOTE: we deliberately do NOT override the src hash here anymore. A previous
  # workaround re-pointed src at the mutable CachyOS pacman mirror
  # (proton-cachyos-slr-*.pkg.tar.zst) via an npins url pin, but the mirror and
  # the GitHub release are different artifacts with different hashes, so forcing
  # the mirror's hash onto the GitHub-release fetch caused a fixed-output hash
  # mismatch. The GitHub release is immutable, so upstream's pinned hash is
  # stable and correct on its own.
  proton-cachyos-upstream =
    (import sources.flake-compat {
      src = sources.nix-proton-cachyos;
    }).defaultNix.packages.${pkgs.stdenv.hostPlatform.system}.proton-cachyos;

  proton-cachyos =
    pkgs.runCommand "proton-cachyos-slr-${proton-cachyos-upstream.version}"
      {
        inherit (proton-cachyos-upstream) version;
        outputs = [
          "out"
          "steamcompattool"
        ];
        meta = proton-cachyos-upstream.meta or { };
      }
      ''
        ln -s ${proton-cachyos-upstream}/share/steam/compatibilitytools.d/proton-cachyos-slr $steamcompattool
        echo "proton-cachyos-slr should not be installed into environments. Use programs.steam.extraCompatPackages instead." > $out
      '';
in
{
  options.customNixOSModules.gamingConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable the gaming-oriented NixOS configuration.

        This module provides a production-grade gaming setup inspired by
        Jovian-NixOS (Steam Deck / SteamOS). It bundles:

        - Steam with remote play, Proton GE and Proton CachyOS compatibility, and extest
        - GameMode performance daemon
        - 32-bit graphics and driver support
        - Gamepad / controller udev rules (uinput, Valve HID devices)

        GPU-specific tuning (AMD kernel boot parameters and early modesetting)
        is gated behind the `gpu` option below, so this module is usable on
        both AMD and NVIDIA machines.

        Used on: anya (AMD gaming/streaming desktop), hanamichi (NVIDIA desktop).
        Reference: https://github.com/Jovian-Experiments/Jovian-NixOS
      '';
    };
    gpu = lib.mkOption {
      type = lib.types.enum [
        "amd"
        "nvidia"
        "none"
      ];
      default = "amd";
      description = ''
        Which GPU vendor the machine uses. Controls vendor-specific tuning:

        - "amd": applies AMD GPU kernel boot parameters (TDR timeouts, TTM page
          pool, scheduler submission depth, IOMMU off) and early `amdgpu`
          modesetting in initrd.
        - "nvidia": skips all AMD-specific tuning. Configure the proprietary
          driver (`hardware.nvidia`, `services.xserver.videoDrivers`) in the
          machine profile.
        - "none": GPU-agnostic; only the common gaming stack (Steam, GameMode,
          32-bit graphics) is applied.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # --- Steam ---
    programs.steam = {
      enable = true;
      remotePlay.openFirewall = true;
      extraCompatPackages = with pkgs; [
        proton-ge-bin
        proton-cachyos
      ];
      extest.enable = true;
    };
    hardware = {
      steam-hardware = {
        enable = true;
      };
      # Firmware is required in stage-1 for early KMS
      enableRedistributableFirmware = true;

      # --- 32-bit support for Wine / Proton ---
      graphics = {
        enable = true;
        enable32Bit = true;
      };
    };
    boot = {
      # ntsync improves Wine/Proton sync performance regardless of GPU vendor.
      kernelModules = [ "ntsync" ];

      # --- AMD GPU boot parameters (from Jovian steamos/boot.nix) ---
      # Only applied on AMD machines; NVIDIA tuning lives in the machine profile.
      kernelParams = lib.mkIf (cfg.gpu == "amd") [
        # Increase kernel log buffer for GPU driver debug traces
        "log_buf_len=4M"

        # Bypass IOMMU for lower latency GPU access
        "amd_iommu=off"

        # Valve-tuned TDR timeouts per ring:
        #   GFX 5s, Compute 10s, SDMA 10s, Video 5s
        "amdgpu.lockup_timeout=5000,10000,10000,5000"

        # 8 GB TTM page pool (in 4K pages) -- minimum for decent gaming perf
        "ttm.pages_min=2097152"

        # Raise hw submission queue depth to avoid GPU work bubbles
        # 4 is the max supported across RDNA2 + RDNA3
        "amdgpu.sched_hw_submission=4"

        # Work around black/white flashes when showing/hiding planes
        "amdgpu.dcdebugmask=0x20000"

        # Disable kernel audit subsystem (not needed for gaming, saves cycles)
        "audit=0"
      ];

      # --- Early AMD GPU modesetting (from Jovian hardware/amd) ---
      initrd.kernelModules = lib.mkIf (cfg.gpu == "amd") [
        "amdgpu"
      ];
    };

    # --- Controller udev rules (from Jovian steamdeck/controller.nix) ---
    services.udev.extraRules = lib.optionalString (!config.hardware.steam-hardware.enable) ''
      # Gamepad emulation via uinput
      KERNEL=="uinput", SUBSYSTEM=="misc", TAG+="uaccess", OPTIONS+="static_node=uinput"

      # Valve USB HID devices (Steam controllers, Steam Deck, etc.)
      SUBSYSTEM=="usb", ATTRS{idVendor}=="28de", MODE="0660", TAG+="uaccess"

      # Valve HID devices over USB hidraw
      KERNEL=="hidraw*", ATTRS{idVendor}=="28de", MODE="0660", TAG+="uaccess"
    '';

    # --- GameMode ---
    programs.gamemode = {
      enable = true;
      enableRenice = true;
    };
  };
}
