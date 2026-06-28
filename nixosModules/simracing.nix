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
        wheelbases and sim racing peripherals, targeting Moza Racing (VID
        346e) and Fanatec (VID 0eb7) hardware:

        - Moza & Fanatec udev rules for serial (Foxblat config), HID (FFB),
          USB, and input device access
        - Foxblat — Linux Moza configuration tool (fork of boxflat, Pit House alt)
        - Oversteer — generic steering wheel manager (rotation, FFB gain,
          autocenter, combine pedals, etc.); also supports Fanatec wheels
        - Joystick and FFB testing utilities (evtest, fftest, jstest)
        - USB autosuspend disabled for Moza/Fanatec devices to prevent drops
        - CDC ACM kernel module for Moza serial communication

        The kernel PIDFF (PID Force Feedback) driver handles all FFB for
        Moza, Fanatec, and other direct-drive wheelbases natively since
        kernel 6.15+.

        Used on: anya (gaming/streaming desktop), hanamichi (gaming desktop).
        Reference: https://github.com/JacKeTUs/universal-pidff
        Reference: https://github.com/giantorth/foxblat (fork of Lawstorant/boxflat)
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # --- Moza Racing & sim racing udev rules ---
    # Include foxblat's own 99-foxblat.rules so it detects devices at runtime
    services.udev.packages = [ pkgs.foxblat ];

    # Additional Moza & Fanatec rules not covered by boxflat's own rules file
    services.udev.extraRules = ''
      # Moza Racing HID raw access (force feedback, device configuration)
      KERNEL=="hidraw*", ATTRS{idVendor}=="346e", MODE="0666", TAG+="uaccess"

      # Moza Racing USB device access
      SUBSYSTEM=="usb", ATTRS{idVendor}=="346e", MODE="0666", TAG+="uaccess"

      # Moza Racing input devices
      SUBSYSTEM=="input", ATTRS{idVendor}=="346e", MODE="0666", TAG+="uaccess"

      # Disable USB autosuspend for Moza devices (prevent connection drops mid-race)
      ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="346e", ATTR{power/autosuspend}="-1"

      # Fanatec HID raw access (force feedback, device configuration)
      KERNEL=="hidraw*", ATTRS{idVendor}=="0eb7", MODE="0666", TAG+="uaccess"

      # Fanatec USB device access (wheelbases, pedals, shifters, handbrakes)
      SUBSYSTEM=="usb", ATTRS{idVendor}=="0eb7", MODE="0666", TAG+="uaccess"

      # Fanatec input devices
      SUBSYSTEM=="input", ATTRS{idVendor}=="0eb7", MODE="0666", TAG+="uaccess"

      # Disable USB autosuspend for Fanatec devices (prevent connection drops mid-race)
      ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="0eb7", ATTR{power/autosuspend}="-1"
    '';

    # --- Kernel modules for sim racing hardware ---
    boot.kernelModules = [
      "cdc_acm" # USB serial (ACM) — required for Moza base serial communication
      "usbhid" # USB HID — explicit for wheelbases, pedals, shifters
    ];

    # --- Sim racing packages ---
    environment.systemPackages = with pkgs; [
      foxblat # Moza Racing configuration tool (fork of boxflat, Linux Pit House alternative)
      oversteer # Generic steering wheel manager (rotation, FFB, autocenter)
      linuxConsoleTools # jstest, fftest — joystick and force feedback testing
      evtest # Input event monitor — useful for debugging HID devices
    ];
  };
}
