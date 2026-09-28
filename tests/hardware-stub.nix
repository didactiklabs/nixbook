# Stand-in for /etc/nixos/hardware-configuration.nix (imported by base.nix) on
# machines that have none, e.g. CI runners, so the profiles can be evaluated:
#   sudo install -D -m 644 tests/hardware-stub.nix /etc/nixos/hardware-configuration.nix
# Evaluation only: never deploy a system built with it.
{
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/boot";
    fsType = "vfat";
  };
  nixpkgs.hostPlatform = "x86_64-linux";
}
