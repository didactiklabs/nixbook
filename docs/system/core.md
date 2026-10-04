# Core system

The **`core`** module (`nixosModules/core.nix`, on by default) is the foundation every machine shares. The **`tools`** module (also on by default) adds system-level tooling, and **`getRevision`** stamps each build with its Git commit.

## Boot

- **systemd-boot** UEFI loader (replaced by Lanzaboote when [Secure Boot](/installation/secure-boot) is on), with a **1-second** menu timeout and the **kernel command-line editor disabled**.
- **Plymouth** splash with a **silent boot**: only errors reach the console (`consoleLogLevel` 3, quiet initrd, quiet udev and systemd status), and no blinking cursor.
- The **latest kernel**, LVM and LUKS (dm-crypt) in the initrd, keyboard backlight in the initrd (to type the LUKS passphrase in the dark), IOMMU, NTFS and exFAT support for external drives.
- `core.amdgpuPsr` controls AMD **Panel Self Refresh** on eDP laptop panels — `"off"` (the long-standing freeze workaround), `"no-su"` (PSR on without Selective Update, the part behind most Rembrandt/Phoenix freezes) or `"on"` (the kernel default).

## Kernel hardening

Sysctls restrict unprivileged BPF, perf events, ICMP redirects, source routing, SUID core dumps, kexec, TTY line-discipline autoloading, `dmesg` and kernel pointers, ptrace scope, and maximise mmap ASLR entropy. Boot parameters add `slab_nomerge` and page-allocator randomisation (`page_alloc.shuffle=1`).

Memory is tuned for zram (`vm.swappiness = 180`, `vm.page-cluster = 0`, watermark tuning).

## Audio and hardware

- **PipeWire** with ALSA and PulseAudio compatibility (PulseAudio itself off), rtkit.
- Firmware, Intel/AMD CPU microcode, **Bluetooth** (BlueZ), uinput.
- **Fingerprint** reader support (fprintd), **firmware updates** (fwupd), time sync (chrony), NetworkManager.

## Security & authentication

- **polkit** (power actions without a password for the local user), **U2F PAM** for login and sudo — YubiKeys and other FIDO keys, with a _"Touch your security key"_ cue shown by greeters, sudo and the lock screen.
- sudo restricted to members of `wheel`.
- **GNOME Keyring** system support: Secret Service, the gcr unlock prompter, the Secret portal backend and PAM unlock at login.
- A `plugdev` group (Yubico's udev rules use it).

See [Security](./security) for Secure Boot, encryption, secrets and the firewall.

## Nix

- **Lix** as the Nix implementation, `nix-command` and flakes enabled.
- A custom **S3 binary cache** (`didactiklabs-nixcache`) in front of cache.nixos.org, which CI fills from `main`.
- Weekly garbage collection (keeps the last 5 generations and 7 days), store optimisation at night.
- The Nix daemon builds at **idle CPU/IO priority** in an OOM-managed slice, so updates don't make the desktop stutter.

## Locale and session

- Time zone Europe/Paris, **en_US** for every locale category, **French (AZERTY)** keyboard (console and XKB).
- Wayland-only: the X server is disabled, `NIXOS_OZONE_WL=1` makes Electron/Chromium apps native Wayland, XDG portals enabled (backends come from the compositor modules).
- Journal capped at 1 GB, core dumps at 500 MB.

## The `tools` module

On by default, `nixosModules/tools.nix` provides:

| Area           | What                                                                                                        |
| -------------- | ----------------------------------------------------------------------------------------------------------- |
| Containers     | **Podman** with the `docker` compatibility alias, a DNS-enabled default network, weekly auto-prune          |
| YubiKey        | udev rules, yubikey-touch-detector, Yubico PIV/OATH/personalisation tools, **GnuPG agent with SSH support** |
| FIDO2 SSH keys | libfido2 and udev rules for `ed25519-sk` / `ecdsa-sk` keys                                                  |
| Controllers    | DualShock 4 driver (ds4drv) user service, game-device udev rules, unprivileged uinput                       |
| Deployment     | `colmena`, [`ginx`](/packages/#ginx) and [`osupdate`](/installation/deploy-and-update#osupdate)             |
| Misc           | OpenVPN, wlsunset, efibootmgr, update-systemd-resolved, pinentry-qt, lsof, KDE Connect (system side)        |

## Git revision stamping

`getRevision` (on by default) writes `/etc/nixos/version` with the remote URL, branch, commit, commit date and a `dirty` flag. The update widgets compare it with the remote — see [Deploy & update](/installation/deploy-and-update#checking-what-is-deployed).
