{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customNixOSModules.simracing;
in
{
  options.customNixOSModules.simracing = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable sim racing hardware support.

        This module provides comprehensive configuration for direct-drive
        wheelbases and sim racing peripherals, primarily targeting Moza
        Racing hardware:

        - Moza udev rules for serial (Boxflat config), HID (FFB), and USB
        - Boxflat — Linux Moza configuration tool (Pit House alternative)
        - Oversteer — generic steering wheel manager (rotation, FFB gain,
          autocenter, combine pedals, etc.)
        - Joystick and FFB testing utilities (evtest, fftest, jstest)
        - USB autosuspend disabled for Moza devices to prevent drops
        - CDC ACM kernel module for Moza serial communication

        The kernel PIDFF (PID Force Feedback) driver handles all FFB for
        Moza and other direct-drive wheelbases natively since kernel 6.15+.

        Used on: anya (gaming/streaming desktop).
        Reference: https://github.com/JacKeTUs/universal-pidff
        Reference: https://github.com/Lawstorant/boxflat
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # --- Moza Racing & sim racing udev rules ---
    # Include boxflat's own 99-boxflat.rules so it detects them at runtime
    # (boxflat checks /etc/udev/rules.d/99-boxflat.rules by filename)
    services.udev.packages = [ pkgs.boxflat ];

    # Additional Moza rules not covered by boxflat's own rules file
    services.udev.extraRules = ''
      # Moza Racing HID raw access (force feedback, device configuration)
      KERNEL=="hidraw*", ATTRS{idVendor}=="346e", MODE="0666", TAG+="uaccess"

      # Moza Racing USB device access
      SUBSYSTEM=="usb", ATTRS{idVendor}=="346e", MODE="0666", TAG+="uaccess"

      # Moza Racing input devices
      SUBSYSTEM=="input", ATTRS{idVendor}=="346e", MODE="0666", TAG+="uaccess"

      # Disable USB autosuspend for Moza devices (prevent connection drops mid-race)
      ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="346e", ATTR{power/autosuspend}="-1"
    '';

    # --- Kernel modules for sim racing hardware ---
    boot.kernelModules = [
      "cdc_acm" # USB serial (ACM) — required for Moza base serial communication
      "usbhid" # USB HID — explicit for wheelbases, pedals, shifters
    ];

    # --- Sim racing packages ---
    environment.systemPackages = with pkgs; [
      boxflat # Moza Racing configuration tool (Linux Pit House alternative)
      oversteer # Generic steering wheel manager (rotation, FFB, autocenter)
      linuxConsoleTools # jstest, fftest — joystick and force feedback testing
      evtest # Input event monitor — useful for debugging HID devices
    ];
  };
}
