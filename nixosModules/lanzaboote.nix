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
  options.customNixOSModules.lanzaboote = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable lanzaboote for UEFI Secure Boot.

        Lanzaboote replaces systemd-boot and signs the kernel and initrd
        with a machine-specific key so that Secure Boot can verify them.

        Automatic provisioning is enabled by default:
        - On first boot, a systemd service generates signing keys.
        - Another service prepares Authenticated Variables on the ESP,
          re-signs all boot artifacts, and triggers a reboot.
        - On the next boot, systemd-boot enrolls the keys into the
          firmware and Secure Boot enforcement begins.

        This is a trust-on-first-use model: the first boot is unsigned,
        subsequent boots are signed and verified.

        After provisioning, verify with:
            bootctl status          (should show Secure Boot: enabled)
            sudo sbctl verify      (all boot entries should be signed)

        When this option is enabled:
        - boot.loader.systemd-boot.enable is forced to false (they are
          mutually exclusive).
        - boot.lanzaboote.enable is set to true with automatic key
          generation and enrollment.
        - The configurationLimit defaults to 10.

        Disable this option on machines that do not use Secure Boot.
      '';
    };
  };

  config = lib.mkIf cfg.lanzaboote.enable {
    # lanzaboote and systemd-boot are mutually exclusive boot loaders.
    boot.loader.systemd-boot.enable = lib.mkForce false;

    boot.lanzaboote = {
      enable = true;
      pkiBundle = "/var/lib/sbctl";
      configurationLimit = 10;

      # Automatically generate signing keys on first boot if they don't exist.
      autoGenerateKeys.enable = true;

      # Automatically enroll keys into the UEFI firmware via systemd-boot.
      # Includes Microsoft keys by default for OptionROM / driver compatibility.
      autoEnrollKeys = {
        enable = true;
        autoReboot = true;
      };
    };

    # sbctl is the tool used to manage Secure Boot keys and sign binaries.
    environment.systemPackages = [ pkgs.sbctl ];
  };
}
