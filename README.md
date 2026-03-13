# Nixbook

[![Build Totoro](https://github.com/didactiklabs/nixbook/actions/workflows/build-totoro.yaml/badge.svg)](https://github.com/didactiklabs/nixbook/actions/workflows/build-totoro.yaml)
[![Build nishinoya](https://github.com/didactiklabs/nixbook/actions/workflows/build-nishinoya.yaml/badge.svg)](https://github.com/didactiklabs/nixbook/actions/workflows/build-nishinoya.yaml)
[![Build anya](https://github.com/didactiklabs/nixbook/actions/workflows/build-anya.yaml/badge.svg)](https://github.com/didactiklabs/nixbook/actions/workflows/build-anya.yaml)

## 🔍 Description

<p align=left>

In this project lies the NixOS configuration files leading to our own custom configured NixOS installation.

It has for objective to be flexible with opt-in/opt-out options while still being able to mutualize some of it.

### Project Goals

The primary goal of Nixbook is to provide a personal, highly customizable, and reproducible NixOS environment. It aims to offer a robust base configuration that can be easily extended and adapted to different machines and use cases, promoting the "everything as code" philosophy through Nix. This allows for consistent deployments and easy management of system configurations.

### Wayland with UEFI BOOT only for now

</p>

## 🚀 Main Features

#### - Reproductibility

<p align=left>

Everything as code and reproductible thanks to Nix.

</p>

#### - Modern Zsh shell

<p align=left>

A bunch of plugins and GNU cli replacers are pre-installed.

</p>

#### - Profiles

<p align=left>

In this project, it's possible to add Nix code on top the base to customize your way out (git config, opt-in/opt-out for features).

</p>

#### - Easy Install and upgrades

<p align=left>

You only need to install the base NixOS iso.

Customization is done via the `profiles` directories.

If it's your first install run (we assume you have colmena installed):

```bash
colmena apply-local --sudo  -v switch
```

To update:

```bash
ginx --source https://github.com/didactiklabs/nixbook -b main --now -- colmena apply-local --sudo
```

or run the alias, effectively doing the same:

```bash
osupdate
```

Profile selected is based on the output of `hostname`.

</p>

#### - Screenshot

with niri:

<img src="./assets/images/screenshot.png" alt="alt text" width="500">

with headless sunshine/moonlight configuration (remote desktop) v1:

<img src="./assets/images/screenshot-demo-sunshine.png" alt="alt text" width="500">

with headless sunshine/moonlight configuration (remote desktop) v2, running windows:

<img src="./assets/images/screenshot-demo-sunshine-windows.png" alt="alt text" width="500">
