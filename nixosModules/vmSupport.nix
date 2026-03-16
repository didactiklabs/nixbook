{
  config,
  lib,
  ...
}:
let
  cfg = config.customNixOSModules.vmSupport;
in
{
  options.customNixOSModules.vmSupport = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        whether to enable VM support (virtio drivers) globally or not
      '';
    };
  };
  config = lib.mkIf cfg.enable {
    boot.initrd.availableKernelModules = [
      "virtio_pci"
      "virtio_blk"
      "virtio_scsi"
      "virtio_net"
    ];
  };
}
