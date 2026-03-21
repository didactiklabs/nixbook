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

        Prerequisites:
        - Enroll your Secure Boot keys with sbctl before switching:
            sudo sbctl create-keys
            sudo sbctl enroll-keys --microsoft
        - Enable Secure Boot in the firmware (UEFI) setup.

        When this option is enabled:
        - boot.loader.systemd-boot.enable is forced to false (they are
          mutually exclusive).
        - boot.lanzaboote.enable is set to true with pkgs.sbctl.
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
    };

    # sbctl is the tool used to manage Secure Boot keys and sign binaries.
    environment.systemPackages = [ pkgs.sbctl ];
  };
}
