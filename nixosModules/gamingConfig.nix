{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customNixOSModules.gamingConfig;
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

        - Steam with remote play, Proton GE compatibility, and extest
        - AMD GPU kernel boot parameters tuned for gaming (TDR timeouts,
          TTM page pool, scheduler submission depth, IOMMU off)
        - Early AMD GPU kernel modesetting with redistributable firmware
        - Gamepad / controller udev rules (uinput, Valve HID devices)
        - GameMode performance daemon
        - 32-bit graphics and driver support

        Used on: anya (gaming/streaming desktop).
        Reference: https://github.com/Jovian-Experiments/Jovian-NixOS
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # --- Steam ---
    programs.steam = {
      enable = true;
      remotePlay.openFirewall = true;
      extraCompatPackages = with pkgs; [ proton-ge-bin ];
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
      # --- AMD GPU boot parameters (from Jovian steamos/boot.nix) ---
      kernelParams = [
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
      kernelModules = [ "ntsync" ];

      initrd.kernelModules = [
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
