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
  # The upstream package only installs to share/steam/compatibilitytools.d/ but
  # NixOS's extraCompatPackages uses lib.makeSearchPathOutput "steamcompattool",
  # requiring a dedicated "steamcompattool" output pointing directly at the tool
  # directory — matching the pattern used by proton-ge-bin in nixpkgs.
  proton-cachyos =
    ((import sources.flake-compat {
      src = sources.nix-proton-cachyos;
    }).defaultNix.packages.${pkgs.stdenv.hostPlatform.system}.proton-cachyos
    ).overrideAttrs
      (old: {
        # CachyOS rebuilds the proton-cachyos-slr tarball in place (same version
        # number, new bytes), so the hash pinned in upstream's versions.json goes
        # stale and the fixed-output `src` fetch fails with a hash mismatch.
        # Override the src fetch hash with the one tracked by the npins
        # `proton-cachyos-slr` url pin (npins/sources.json) instead of hardcoding
        # it here. To refresh: re-point that pin at the tarball the mirror
        # currently serves (`npins add --name proton-cachyos-slr url <tarball>`),
        # which records the new hash.
        src = old.src.overrideAttrs (_: {
          outputHash = sources.proton-cachyos-slr.hash;
        });
        outputs = [
          "out"
          "steamcompattool"
        ];
        installPhase = ''
          runHook preInstall
          tar -I zstd -xf $src
          mkdir -p $steamcompattool
          cp -r usr/share/steam/compatibilitytools.d/proton-cachyos-slr/* $steamcompattool/
          echo "${
            old.pname or "proton-cachyos-slr"
          } should not be installed into environments. Use programs.steam.extraCompatPackages instead." > $out
          runHook postInstall
        '';
      });
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
