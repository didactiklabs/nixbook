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
        Whether to enable VirtIO paravirtual driver support in the initrd.

        Adds the following kernel modules to boot.initrd.availableKernelModules
        so the system can boot inside a QEMU/KVM or other virtio-based hypervisor:
          - virtio_pci  — VirtIO PCI bus driver
          - virtio_blk  — VirtIO block device (virtual disk)
          - virtio_scsi — VirtIO SCSI host controller
          - virtio_net  — VirtIO network interface

        Enable this when building a VM image (e.g. via nixos-generators) or when
        testing the configuration with `test-iso` in QEMU.  Not needed on bare-metal.
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
