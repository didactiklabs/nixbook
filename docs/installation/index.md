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
- For the installer: a **wired Ethernet connection** with DHCP. The live ISO does not configure Wi-Fi, and the installation downloads packages and clones the repository.
- Nix on the machine that builds the ISO.

## The life of a machine

```
 build ISO ─▶ boot ISO ─▶ installer (disk, hostname, LUKS, user, LVM)
                              │
                              ▼
                     reboot ─▶ first-boot bootstrap
                              (hardware config, LUKS, clone repo,
                               colmena apply-local)
                              │
                              ▼
                     reboot ─▶ final system ─▶ Secure Boot keys enrolled
                                               (if lanzaboote is on)
                              │
                              ▼
                     day to day: osupdate / update widget / colmena apply-local
```

1. [Build and boot the installer ISO](./iso), answer its questions.
2. The first boot [bootstraps](./iso#first-boot) the real configuration automatically.
3. If the profile enables it, [Secure Boot](./secure-boot) provisions itself over the next boots.
4. From then on, [update](./deploy-and-update) with `osupdate`, the desktop shell's update widget, or `colmena apply-local`.
