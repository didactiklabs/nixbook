# Installer ISO

Nixbook builds its own NixOS live ISO with an interactive installer that partitions the disk with [Disko](https://github.com/nix-community/disko), optionally encrypts it with LUKS and installs the machine's full configuration in one go: one reboot and it is ready.

## Prerequisites

- **Nix** on the build machine.
- **UEFI** boot on the target machine.
- **Internet** on the target: the installer downloads the nixbook repository and the packages. Ethernet works out of the box; Wi-Fi is set up from the installer (`nmtui`).
- The machine must be defined in `hive.nix` (with its profile in `profiles/`): the installer lists those.
- **8 GB of RAM** or more is recommended: the configuration is evaluated in the live system's memory (about 3 GB).

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

This boots the ISO in QEMU with UEFI firmware and KVM acceleration, 8 GB of RAM, 4 CPUs and a 64 GB virtual disk. Profiles meant for VMs can enable [`customNixOSModules.vmSupport`](/system/hardware#virtual-machines) for VirtIO drivers in the initrd.

## Run the installer

Boot the target from the USB drive. The installer starts automatically (or run `sudo installer`), downloads the nixbook configuration (`main`) and asks everything before touching the disk:

1. **Network** — without a connection, connect to Wi-Fi (`nmtui`) or plug in Ethernet and retry.
2. **Machine** — one of the machines in `hive.nix`. The keyboard switches to that machine's console layout, so the LUKS passphrase is typed the way the initrd will read it.
3. **Disk** — the target disk (the installer's USB drive, DVD and zram devices are not listed).
4. **Disk encryption** — optionally LUKS full-disk encryption and its passphrase.
5. **Partition layout** — the recommended layout (swap the size of the RAM, at most a quarter of the disk, for hibernation; ext4 `/` on the rest), or custom LVM volumes (name, size, file system, mount point; a `/` volume is required).
6. **Passwords** — one for each account the machine's profile defines.
7. **Confirmation** — a summary; nothing is erased before you confirm.

It then runs unattended:

1. wipes the disk and partitions it with Disko;
2. generates `/etc/nixos/hardware-configuration.nix` and adds the LUKS device to it (`nixos-generate-config` cannot see a LUKS container under LVM);
3. builds the machine's configuration, exactly as `colmena build` evaluates it, straight into the new disk's Nix store;
4. installs it with `nixos-install` and sets the passwords.

The full log is copied to `/var/log/nixbook-install.log` on the new system. If a step fails, fix the cause and run `sudo installer` again.

To install from another branch or a fork:

```bash
sudo NIXBOOK_BRANCH=my-branch NIXBOOK_REPO=https://github.com/me/nixbook installer
```

::: danger
Confirming erases the selected disk entirely.
:::

## First boot

Remove the USB drive and reboot: the machine boots straight into its final configuration. If the profile enables [Secure Boot](./secure-boot), its keys are generated and enrolled over the first boots (the machine reboots once by itself).
