# Nixbook

[![Build Totoro](https://github.com/didactiklabs/nixbook/actions/workflows/build-totoro.yaml/badge.svg)](https://github.com/didactiklabs/nixbook/actions/workflows/build-totoro.yaml)
[![Build nishinoya](https://github.com/didactiklabs/nixbook/actions/workflows/build-nishinoya.yaml/badge.svg)](https://github.com/didactiklabs/nixbook/actions/workflows/build-nishinoya.yaml)
[![Build anya](https://github.com/didactiklabs/nixbook/actions/workflows/build-anya.yaml/badge.svg)](https://github.com/didactiklabs/nixbook/actions/workflows/build-anya.yaml)

## 🔍 Description

### Project Goals

The primary goal of Nixbook is to provide a personal, highly customizable, and reproducible NixOS environment. It aims to offer a robust base configuration that can be easily extended and adapted to different machines and use cases, promoting the "everything as code" philosophy through Nix. This allows for consistent deployments and easy management of system configurations.

### Wayland with UEFI Boot

Currently supports Wayland display servers with UEFI boot only.

## 🚀 Main Features

**Reproducibility**

Everything is configured as code with Nix, ensuring consistent and reproducible deployments across systems.

**Modern Zsh Shell**

Pre-configured with various plugins and GNU CLI replacements for an enhanced shell experience.

**Machine Profiles**

Customize your setup per machine using profile configurations. Add custom Nix code for features like git configuration and opt-in/opt-out functionality.

**Easy Installation and Updates**

After installing the base NixOS ISO, customize your system using profiles. Profile selection is automatic based on your hostname.

Initial setup:

```bash
colmena apply-local --sudo -v switch
```

Update your system:

```bash
osupdate
```

Or manually:

```bash
ginx --source https://github.com/didactiklabs/nixbook -b main --now -- colmena apply-local --sudo
```

**Screenshots**

Niri:

<img src="./assets/images/screenshot.png" alt="Niri configuration" width="500">

Headless sunshine/moonlight (remote desktop) v1:

<img src="./assets/images/screenshot-demo-sunshine.png" alt="Sunshine/moonlight v1" width="500">

Headless sunshine/moonlight (remote desktop) v2 with Windows:

<img src="./assets/images/screenshot-demo-sunshine-windows.png" alt="Sunshine/moonlight v2 Windows" width="500">
