# Secure Boot

Nixbook supports UEFI Secure Boot through [Lanzaboote](https://github.com/nix-community/lanzaboote), with **fully automatic provisioning**: no manual key generation or enrolment.

## Enable it

In the machine profile (e.g. `profiles/tanjiro/default.nix`):

```nix
customNixOSModules.lanzaboote.enable = true;
```

Lanzaboote replaces systemd-boot and signs the kernel and initrd with a machine-specific key. `sbctl` is installed for inspection.

## What happens automatically

Over the first boots after `colmena apply-local --sudo` (or after installing with the installer):

1. **First boot under Lanzaboote** — a systemd service generates the Secure Boot signing keys (PK, KEK, db) in `/var/lib/sbctl`.
2. **Same boot** — another service prepares EFI Authenticated Variables on the ESP, re-signs every boot artifact and triggers an automatic reboot.
3. **Next boot** — systemd-boot enrols the keys into the firmware. Secure Boot enforcement begins.

This is a **trust-on-first-use** model: the first boot is unsigned, every following boot is signed and verified. Microsoft's keys are included by default for OptionROM and driver compatibility.

::: tip Your firmware must be in Setup Mode
Automatic enrolment needs the firmware's Secure Boot to be in **Setup Mode** (no platform key enrolled). On most machines: enter the UEFI setup, clear or reset the Secure Boot keys, and enable Secure Boot.
:::

## Verify

```bash
bootctl status        # → Secure Boot: enabled (user)
sudo sbctl verify     # every boot entry is signed
```

## Recommendations

- Use **LUKS full-disk encryption** with Secure Boot: the signing keys live on the local disk in `/var/lib/sbctl`.
- Set a **UEFI/BIOS password** so Secure Boot cannot be switched off from the firmware.
- The key generation and enrolment services are **idempotent**: once keys are generated and enrolled they do nothing.

Both `core` and Lanzaboote keep the boot menu's kernel command-line editor **disabled** (no `init=/bin/sh` from the keyboard) and use a 1-second menu timeout.
