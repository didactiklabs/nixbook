# Nixbook Custom Module Options

> **Auto-generated** from the Nix module definitions.
> Run `nix-build docs/generate-docs.nix && cp result/MODULES.md docs/MODULES.md` to regenerate.

## Table of Contents

### NixOS Modules

- [caCertificates](#cacertificates)
- [core](#core)
- [getRevision](#getrevision)
- [greetd](#greetd)
- [hyprland](#hyprland)
- [laptopProfile](#laptopprofile)
- [netbird-tools](#netbird-tools)
- [networkManager](#networkmanager)
- [niri](#niri)
- [printTools](#printtools)
- [sunshine](#sunshine)
- [sway](#sway)
- [tailscale](#tailscale)
- [tools](#tools)
- [vmSupport](#vmsupport)

### Home Manager Modules

- [atuinConfig](#atuinconfig)
- [cliTools](#clitools)
- [desktopApps](#desktopapps)
- [devTools](#devtools)
- [dmsConfig](#dmsconfig)
- [fastfetchConfig](#fastfetchconfig)
- [fcitx5Config](#fcitx5config)
- [fontConfig](#fontconfig)
- [gitConfig](#gitconfig)
- [gojiConfig](#gojiconfig)
- [gtkConfig](#gtkconfig)
- [hyprlandConfig](#hyprlandconfig)
- [kittyConfig](#kittyconfig)
- [kubeConfig](#kubeconfig)
- [kubeTools](#kubetools)
- [kubeswitchConfig](#kubeswitchconfig)
- [niriConfig](#niriconfig)
- [nixvimConfig](#nixvimconfig)
- [opencodeConfig](#opencodeconfig)
- [rtk](#rtk)
- [sshConfig](#sshconfig)
- [starship](#starship)
- [stylixConfig](#stylixconfig)
- [swayConfig](#swayconfig)
- [thunderbirdConfig](#thunderbirdconfig)
- [volumeScript](#volumescript)
- [vscode](#vscode)
- [zshConfig](#zshconfig)

---

# NixOS Modules (`customNixOSModules`)

## caCertificates

### `customNixOSModules.caCertificates.bealv.enable`

- **Type:** `boolean`
- **Default:** `false`

whether to enable caCertificates globally or not.

### `customNixOSModules.caCertificates.didactiklabs.enable`

- **Type:** `boolean`
- **Default:** `false`

whether to enable caCertificates globally or not.

### `customNixOSModules.caCertificates.logicmg.enable`

- **Type:** `boolean`
- **Default:** `false`

whether to enable caCertificates globally or not.

---

## core

### `customNixOSModules.core.enable`

- **Type:** `boolean`
- **Default:** `true`

Whether to enable the core NixOS module. Provides bootloader, kernel, audio, bluetooth, security, and nix daemon configuration.

---

## getRevision

### `customNixOSModules.getRevision.enable`

- **Type:** `boolean`
- **Default:** `true`

Whether to enable git revision tracking. Writes git metadata (url, branch, rev, lastModifiedDate) to /etc/nixos/version.

---

## greetd

### `customNixOSModules.greetd.enable`

- **Type:** `boolean`
- **Default:** `false`

whether to enable greeter globally or not.

---

## hyprland

### `customNixOSModules.hyprland.enable`

- **Type:** `boolean`
- **Default:** `false`

whether to enable hyprland config globally or not

---

## laptopProfile

### `customNixOSModules.laptopProfile.enable`

- **Type:** `boolean`
- **Default:** `false`

whether to enable laptopProfile globally or not

---

## netbird-tools

### `customNixOSModules.netbird-tools.enable`

- **Type:** `boolean`
- **Default:** `true`

Whether to enable the netbird tools module. Provides the nswitch CLI tool for switching Netbird networks.

---

## networkManager

### `customNixOSModules.networkManager.enable`

- **Type:** `boolean`
- **Default:** `true`

whether to enable networkManager globally or not

---

## niri

### `customNixOSModules.niri.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable Niri config globally or not. Niri is a scrollable-tiling Wayland compositor.

---

## printTools

### `customNixOSModules.printTools.enable`

- **Type:** `boolean`
- **Default:** `false`

whether to enable printTools globally or not.

---

## sunshine

### `customNixOSModules.sunshine.enable`

- **Type:** `boolean`
- **Default:** `false`

whether to enable sunshine globally or not

---

## sway

### `customNixOSModules.sway.enable`

- **Type:** `boolean`
- **Default:** `false`

whether to enable sway config globally or not

---

## tailscale

### `customNixOSModules.tailscale.enable`

- **Type:** `boolean`
- **Default:** `true`

Whether to enable tailscale fix routes and tswitch helper. Provides a persistent systemd service to fix conflicting Tailscale routes and a tswitch CLI tool for switching Tailnets.

---

## tools

### `customNixOSModules.tools.enable`

- **Type:** `boolean`
- **Default:** `true`

Whether to enable the tools NixOS module. Provides podman, yubikey tools, ds4 controller support, and system utilities.

---

## vmSupport

### `customNixOSModules.vmSupport.enable`

- **Type:** `boolean`
- **Default:** `false`

whether to enable VM support (virtio drivers) globally or not

---

# Home Manager Modules (`customHomeManagerModules`)

## atuinConfig

### `customHomeManagerModules.atuinConfig.didactiklabs.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable atuinConfig config globally or not.

---

## cliTools

### `customHomeManagerModules.cliTools.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable CLI utilities and tools

---

## desktopApps

### `customHomeManagerModules.desktopApps.enable`

- **Type:** `boolean`
- **Default:** `false`

whether to enable desktopApps globally or not

---

## devTools

### `customHomeManagerModules.devTools.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable development tools

---

## dmsConfig

### `customHomeManagerModules.dmsConfig.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable DankMaterialShell (DMS), a Quickshell-based desktop shell with system monitoring, dynamic theming, and custom widgets.

### `customHomeManagerModules.dmsConfig.showDock`

- **Type:** `boolean`
- **Default:** `false`

Show the dock

---

## fastfetchConfig

### `customHomeManagerModules.fastfetchConfig.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable fastfetchConfig config globally or not.

---

## fcitx5Config

### `customHomeManagerModules.fcitx5Config.enable`

- **Type:** `boolean`
- **Default:** `false`

whether to enable fcitx5 with Japanese input support (mozc) or not

---

## fontConfig

### `customHomeManagerModules.fontConfig.enable`

- **Type:** `boolean`
- **Default:** `false`

whether to enable font config globally or not

---

## gitConfig

### `customHomeManagerModules.gitConfig.enable`

- **Type:** `boolean`
- **Default:** `false`

whether to enable gitConfig globally or not

---

## gojiConfig

### `customHomeManagerModules.gojiConfig.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable gojiConfig config globally or not.

---

## gtkConfig

### `customHomeManagerModules.gtkConfig.enable`

- **Type:** `boolean`
- **Default:** `false`

whether to enable gtkConfig globally or not

---

## hyprlandConfig

### `customHomeManagerModules.hyprlandConfig.enable`

- **Type:** `boolean`
- **Default:** `false`

whether to enable hyprland config globally or not

---

## kittyConfig

### `customHomeManagerModules.kittyConfig.enable`

- **Type:** `boolean`
- **Default:** `false`

whether to enable kittyConfig globally or not

---

## kubeConfig

### `customHomeManagerModules.kubeConfig.bealv.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable the bealv OIDC kubeconfigs.

### `customHomeManagerModules.kubeConfig.didactiklabs.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable the didactiklabs OIDC kubeconfig.

### `customHomeManagerModules.kubeConfig.logicmg.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable the logicmg OIDC kubeconfig.

---

## kubeTools

### `customHomeManagerModules.kubeTools.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable Kubernetes tools and utilities (kubectl, helm, k9s, kubeswitch, etc.).

---

## kubeswitchConfig

### `customHomeManagerModules.kubeswitchConfig.enable`

- **Type:** `boolean`
- **Default:** `false`

whether to enable kubeswitch configuration or not

---

## niriConfig

### `customHomeManagerModules.niriConfig.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable Niri config globally or not. Niri is a scrollable-tiling Wayland compositor.

---

## nixvimConfig

### `customHomeManagerModules.nixvimConfig.enable`

- **Type:** `boolean`
- **Default:** `false`

whether to enable nixvimConfig globally or not

---

## opencodeConfig

### `customHomeManagerModules.opencodeConfig.enable`

- **Type:** `boolean`
- **Default:** `false`

whether to enable opencodeConfig or not

---

## rtk

### `customHomeManagerModules.rtk.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable RTK (Rust Token Killer) - a CLI proxy that reduces LLM token consumption by 60-90% on common development commands.

---

## sshConfig

### `customHomeManagerModules.sshConfig.enable`

- **Type:** `boolean`
- **Default:** `false`

whether to enable sshConfig globally or not

---

## starship

### `customHomeManagerModules.starship.enable`

- **Type:** `boolean`
- **Default:** `false`

whether to enable starship globally or not

---

## stylixConfig

### `customHomeManagerModules.stylixConfig.enable`

- **Type:** `boolean`
- **Default:** `true`

Whether to enable stylix theming configuration.

---

## swayConfig

### `customHomeManagerModules.swayConfig.enable`

- **Type:** `boolean`
- **Default:** `false`

whether to enable sway config globally or not

---

## thunderbirdConfig

### `customHomeManagerModules.thunderbirdConfig.enable`

- **Type:** `boolean`
- **Default:** `false`

whether to enable thunderbirdConfig globally or not

---

## volumeScript

### `customHomeManagerModules.volumeScript.enable`

- **Type:** `boolean`
- **Default:** `true`

Whether to enable the volume control script and keybindings.

---

## vscode

### `customHomeManagerModules.vscode.enable`

- **Type:** `boolean`
- **Default:** `false`

whether to enable vscode globally or not

---

## zshConfig

### `customHomeManagerModules.zshConfig.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable zsh configuration and shell integrations.
