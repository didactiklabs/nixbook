# Installation overview

There are three ways to use Nixbook:

| You want to…                                   | Go to                                                      |
| ---------------------------------------------- | ---------------------------------------------------------- |
| Install a new machine from scratch             | [Installer ISO](./iso)                                     |
| Apply Nixbook to an existing NixOS install     | [Deploy & update](./deploy-and-update#first-deployment)    |
| Use only the dotfiles on Ubuntu, Fedora, Arch… | [Home Manager on other distros](./home-manager-standalone) |

## Requirements

- **UEFI** firmware. Legacy BIOS boot is not supported.
- A **profile** for the machine: its hostname must match a directory in `profiles/` (currently `totoro`, `tanjiro`, `anya`, `nishinoya`, `hanamichi`). To add one, see [Adding a machine](/machines/adding-a-machine).
- For the installer: an **internet connection** (Ethernet, or Wi-Fi set up from the installer) and 8 GB of RAM or more.
- Nix on the machine that builds the ISO.

## The life of a machine

```
 build ISO ─▶ boot ISO ─▶ installer (machine, disk, LUKS, LVM, passwords)
                              │  partitions, builds and installs
                              │  the machine's full configuration
                              ▼
                     reboot ─▶ final system ─▶ Secure Boot keys enrolled
                                               (if lanzaboote is on)
                              │
                              ▼
                     day to day: osupdate / update widget / colmena apply-local
```

1. [Build and boot the installer ISO](./iso), answer its questions.
2. Reboot: the machine [starts in its final configuration](./iso#first-boot).
3. If the profile enables it, [Secure Boot](./secure-boot) provisions itself over the next boots.
4. From then on, [update](./deploy-and-update) with `osupdate`, the desktop shell's update widget, or `colmena apply-local`.
