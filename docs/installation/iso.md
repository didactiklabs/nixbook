# Installer ISO

Nixbook builds its own NixOS live ISO with an interactive installer that partitions the disk with [Disko](https://github.com/nix-community/disko), optionally encrypts it with LUKS, installs a minimal system and then bootstraps the full profile on first boot.

## Prerequisites

- **Nix** on the build machine.
- **UEFI** boot on the target machine.
- **Wired Ethernet with DHCP** on the target: the ISO downloads packages and clones the nixbook repository during installation; Wi-Fi is not configured on the live system.
- The **hostname** you will enter must match an existing profile in `profiles/`.

## Build the ISO

```bash
nix-build default.nix -A buildIso
# or, in the devenv shell:
build-iso
```

The ISO is written under `./result/iso/`. Flash it to a USB drive:

```bash
sudo dd if=./result/iso/*.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

Replace `/dev/sdX` with your USB device (check with `lsblk` — `dd` overwrites the whole device).

## Try it in a VM first

```bash
nix-build default.nix -A testVm && ./result/bin/test-iso-vm
# or: test-iso
```

This boots the ISO in QEMU with UEFI firmware and KVM acceleration, 4 GB of RAM, 4 CPUs and a 64 GB virtual disk. Profiles meant for VMs can enable [`customNixOSModules.vmSupport`](/system/hardware#virtual-machines) for VirtIO drivers in the initrd.

## Run the installer

Boot the target from the USB drive. The installer starts automatically (or run `sudo installer`) and walks you through:

1. **Disk selection** — pick the target disk from the detected block devices.
2. **Hostname** — must match a profile (`totoro`, `tanjiro`, `anya`, `nishinoya`, `hanamichi`, …).
3. **Disk encryption** — optionally enable LUKS full-disk encryption and set its passphrase.
4. **User account** — a username and password.
5. **Partition layout** — define LVM logical volumes one by one (name, size, filesystem, mount point). A root volume (`/`) is mandatory.
6. **Formatting and installation** — the disk is wiped, partitioned with Disko and `nixos-install` runs.

::: danger
Step 6 erases the selected disk entirely.
:::

## First boot

After the installation the machine reboots into a minimal bootstrap system, which automatically:

1. **Regenerates** `/etc/nixos/hardware-configuration.nix`, now with the real file systems.
2. **Injects the LUKS device** into it if encryption was enabled (`nixos-generate-config` cannot see a LUKS container under LVM).
3. **Clones nixbook** from GitHub and runs `colmena apply-local --sudo` to apply the full profile. _This needs internet access._
4. **Cleans up** the bootstrap files and reboots into the final system.

After this second reboot the machine is fully configured. If the profile enables [Secure Boot](./secure-boot), key provisioning continues automatically over the next boots.
