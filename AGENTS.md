# AI Agents Guide

## Project Overview

**Nixbook** is a reproducible NixOS configuration repository providing declarative system management for multiple machines using the Nix programming language.

**Repository:** `git@github.com:didactiklabs/nixbook.git`
**Primary Goal:** Create a robust, reproducible NixOS environment with modern Wayland display servers and UEFI boot support.

## Key Statistics

- **Nix Files:** 142 files (~11,687 lines of code)
- **Active Machines:** 4 (totoro, anya, nishinoya, tanjiro)
- **Home Manager Modules:** 32 (27 standalone files + 5 subdirectories)
- **NixOS Modules:** 19 files
- **Custom Packages:** 10
- **CI/CD Workflows:** 2
- **NixVim Plugins:** 25
- **VSCode Extensions:** 32
- **Pinned Dependencies:** 26
- **Assets:** 39 files

## Core Tools

- `NixOS` - Linux distribution with declarative configuration
- `Colmena` - Declarative machine deployment tool
- `npins` - Nix dependency pinning and source management
- `Home Manager` - User-level configuration management
- `agenix` - Age-based secrets management
- `Disko` - Declarative disk partitioning
- `Lanzaboote` - UEFI Secure Boot support

## Directory Structure

### Configuration Layers

```
profiles/{hostname}/              Machine-specific configurations
  ├── configuration.nix
  ├── default.nix
  └── {username}/                 User-specific overrides

nixosModules/                     System-level modules (19 files)
homeManagerModules/               User-level modules (32 entries)
base.nix                          Core entry point
hive.nix                          Colmena deployment config
```

### Dependency & Package Management

- `npins/` - Pinned external dependencies (nixpkgs, home-manager, agenix, disko, stylix, lanzaboote, etc.)
- `customPkgs/` - 10 custom packages (ginx, goji, ytui, jtui, crd-wizard, etc.)
- `assets/` - Static assets: themes, plugins, images, certificates, VPN configs

### Installation & Deployment

- `installer/` - Interactive NixOS installer with LUKS encryption, LVM, and Disko support
- `.github/workflows/` - GitHub Actions CI/CD for all 4 machines
- `devenv.nix/.envrc` - Development environment with direnv integration
- `docs/` - Auto-generated module documentation (generate-docs.nix, MODULES.md)

## NixOS Modules (19 files)

| Module               | Lines | Purpose                                                                                                                                                                                                                      |
| -------------------- | ----- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `core.nix`           | 456   | Foundational system: systemd-boot UEFI, plymouth, latest kernel, LVM, LUKS, PipeWire audio, kernel sysctl hardening, security (rtkit, polkit, U2F PAM), Lix nix daemon with S3 cache, fprintd, chrony, fwupd, networkmanager |
| `userConfig.nix`     | 241   | User management framework with mkUser helper, Home Manager integration, Qt theming, Go dev environment                                                                                                                       |
| `tools.nix`          | 165   | System-level tooling: Podman with Docker compat, YubiKey support, system packages, DS4 controller service                                                                                                                    |
| `gamingConfig.nix`   | 106   | Gaming: Steam with Proton GE, AMD GPU kernel params, controller udev rules, GameMode                                                                                                                                         |
| `tailscale.nix`      | 94    | Tailscale VPN with route-conflict workarounds, tswitch fzf-based TUI for Tailnet switching                                                                                                                                   |
| `getRevision.nix`    | 86    | Git metadata embedding: writes JSON to /etc/nixos/version with remote, branch, commit, date                                                                                                                                  |
| `niri.nix`           | 77    | Niri scrollable tiling compositor: fuzzel, grimblast, wl-clipboard, xwayland-satellite                                                                                                                                       |
| `netbird-tools.nix`  | 76    | NetBird WireGuard VPN: daemon setup, nswitch fzf-based TUI for network selection                                                                                                                                             |
| `lanzaboote.nix`     | 70    | UEFI Secure Boot via lanzaboote: replaces systemd-boot, auto-generates/enrolls signing keys, sbctl                                                                                                                           |
| `caCertificates.nix` | 70    | Custom CA certificates: per-org enable options (bealv, didactiklabs, logicmg)                                                                                                                                                |
| `greetd.nix`         | 69    | Login manager: tuigreet TUI greeter with clock, session memory, dynamic session list, U2F PAM auth                                                                                                                           |
| `laptopProfile.nix`  | 68    | Laptop optimizations: lid-switch handling, power-profiles-daemon, thermald, SATA power mgmt, deep sleep                                                                                                                      |
| `firewall.nix`       | 60    | NixOS stateful firewall: nftables backend, deny-by-default inbound, configurable ports. Disabled by default                                                                                                                  |
| `sunshine.nix`       | 52    | Remote desktop streaming: Sunshine game-streaming server as user systemd service                                                                                                                                             |
| `hyprland.nix`       | 50    | Hyprland dynamic tiling compositor: wlr portal, U2F PAM for hyprlock                                                                                                                                                         |
| `printTools.nix`     | 47    | Printing/scanning: CUPS, ipp-usb, Avahi mDNS, SANE with airscan                                                                                                                                                              |
| `sway.nix`           | 37    | Sway i3-like compositor using SwayFX fork (blur, rounded corners, shadows)                                                                                                                                                   |
| `vmSupport.nix`      | 37    | VirtIO support: adds virtio kernel modules to initrd for QEMU/KVM. Disabled by default                                                                                                                                       |
| `default.nix`        | 22    | Module imports aggregator                                                                                                                                                                                                    |

## Home Manager Modules (32 entries)

**Core User Configuration:**

- `entrypoint.nix` (108 LOC) - Profile validation and MIME defaults
- `commonShellConfig.nix` (117 LOC) - Shared shell environment: packages, aliases
- `zshConfig.nix` (101 LOC) - Zsh with fast-syntax-highlighting, autopair
- `gitConfig.nix` (152 LOC) - Git configuration with user-specific overrides, difftastic

**Terminal & Shell:**

- `kittyConfig.nix` (153 LOC) - Terminal emulator with themes
- `starshipConfig.nix` (129 LOC) - Prompt with git info and nix integration
- `atuinConfig.nix` (46 LOC) - Shell history sync (per-environment support)
- `cliTools.nix` (49 LOC) - CLI utilities (bat, eza, ripgrep, etc.)

**Desktop Environments:**

- `hyprland/` - Hyprland compositor (3 files, 442 LOC): hyprlandConfig.nix, hyprlockConfig.nix
- `niri/` - Niri scrollable compositor (2 files, 721 LOC): niriConfig.nix
- `sway/` - Sway i3-like compositor (2 files, 414 LOC): swayConfig.nix
- `gtkConfig.nix` (92 LOC) - GTK appearance and theming
- `fontConfig.nix` (68 LOC) - Font management
- `stylixConfig.nix` (81 LOC) - Declarative theming system (Stylix)
- Rofi launcher with OneDark color scheme

**Development:**

- `devTools.nix` (86 LOC) - Languages and dev tools
- `goji.nix` (259 LOC) - AI-powered conventional commits with emoji support
- `nixvim/` - NeoVim with 25 plugins (28 files, 1,249 LOC): LSP, Treesitter, Telescope, neo-tree, etc.
- `opencodeConfig.nix` (48 LOC) - OpenCode AI coding assistant: gemini-auth + anthropic-oauth plugins

**Kubernetes & DevOps:**

- `k9sConfig.nix` (336 LOC) - K9s dashboard configuration
- `kubeTools.nix` (155 LOC) - kubectl, helm, kubeswitch, k9s, kubeconfigs setup
- `kubeswitchConfig.nix` (55 LOC) - Kubernetes context switcher

**Applications:**

- `dmsConfig.nix` (273 LOC) - DankMaterialShell (DMS) desktop shell: Quickshell-based compositor-agnostic top bar and dock
- `fastfetchConfig.nix` (167 LOC) - System information display with custom logo
- `desktopApps.nix` (63 LOC) - Firefox, Dolphin, MPV, imv, zathura setup
- `dolphinConfig.nix` (31 LOC) - File manager configuration
- `mpvConfig.nix` (34 LOC) - Media player configuration
- `thunderbirdConfig.nix` (34 LOC) - Email client configuration

**Infrastructure & Tools:**

- `fcitx5Config.nix` (71 LOC) - Input method framework (CJK support)
- `rtkConfig.nix` (52 LOC) - RTK CLI proxy for LLM token optimization
- `sshConfig.nix` (43 LOC) - SSH key management
- `vscode/` - VSCode with 32 extensions (4 .nix + 2 .sh files, 982 LOC)

## Machine Profiles (4 machines)

### totoro - Main Development Laptop

- **Location:** `profiles/totoro/`
- **User:** khoa
- **Hardware:** ASUS ZenBook UM6702 (NVIDIA disabled, modesetting-only)
- **Primary WM:** Niri
- **NixOS Modules:** laptopProfile, greetd, niri, caCertificates (bealv + didactiklabs), lanzaboote
- **Special Features:** KDE Connect, Bluetooth, Nextcloud client systemd service, multi-monitor niri config, Moonlight Qt
- **Work Environments:** didactiklabs, bealv kubeconfigs
- **Home Manager Modules:** cliTools, devTools, fontConfig, gitConfig, gtkConfig, sshConfig, starship, niriConfig, fastfetchConfig, desktopApps, kubeTools, nixvimConfig, gojiConfig, atuinConfig, kittyConfig, zshConfig, kubeswitchConfig, fcitx5Config, thunderbirdConfig, opencodeConfig, rtk, dmsConfig

### tanjiro - Development Laptop (Framework)

- **Location:** `profiles/tanjiro/`
- **User:** khoa
- **Hardware:** Framework 13-inch AMD AI 300 series (via nixos-hardware)
- **Primary WM:** Niri
- **NixOS Modules:** laptopProfile, greetd, niri, caCertificates (bealv + didactiklabs), lanzaboote, firewall
- **Special Features:** ClamAV daemon + updater, sudo requires password, Tailscale/NetBird disabled
- **Work Environments:** didactiklabs, bealv kubeconfigs
- **Home Manager Modules:** cliTools, devTools, fontConfig, gitConfig, gtkConfig, sshConfig, starship, niriConfig, fastfetchConfig, desktopApps, kubeTools, nixvimConfig, gojiConfig, atuinConfig, kittyConfig, zshConfig, kubeswitchConfig, thunderbirdConfig, opencodeConfig, rtk, dmsConfig

### anya - Gaming/Streaming Desktop

- **Location:** `profiles/anya/`
- **User:** khoa
- **Primary WM:** Sway (SwayFX) - auto-login, no greeter
- **NixOS Modules:** gamingConfig, sunshine, sway, caCertificates (bealv + didactiklabs), openssh
- **Special Features:** Wake-on-LAN, Steam Big Picture auto-launch, Proton GE, GameMode, AMD GPU tuning, Immich photo sync timers, headless virtual display for Sunshine streaming
- **Work Environments:** didactiklabs, bealv kubeconfigs
- **Home Manager Modules:** fontConfig, gitConfig, gtkConfig, sshConfig, starship, swayConfig, nixvimConfig, fastfetchConfig, atuinConfig, kittyConfig, zshConfig, dmsConfig
- **Extra packages:** wineWow64Packages.waylandFull, firefox

### nishinoya - Secondary Development Laptop

- **Location:** `profiles/nishinoya/`
- **User:** aamoyel
- **Primary WM:** Niri
- **NixOS Modules:** laptopProfile, greetd, niri, caCertificates (didactiklabs + logicmg)
- **Special Features:** KDE Connect, Yubico security key lock on removal, unprivileged port access (sysctl port_start=80)
- **Work Environments:** didactiklabs, logicmg kubeconfigs
- **Extra Packages:** Google Chrome, GitKraken, Slack, Kanidm, Moonlight Qt, immich-go, oapi-codegen
- **Home Manager Modules:** cliTools, devTools, fontConfig, gitConfig, gtkConfig, sshConfig, starship, niriConfig, fastfetchConfig, desktopApps, vscode, kubeTools, nixvimConfig, gojiConfig, atuinConfig, kittyConfig, zshConfig, kubeswitchConfig, fcitx5Config, dmsConfig

## Key Features

### Desktop Environments (Wayland-only)

- **Niri** - Scrollable tiling compositor (preferred)
- **Hyprland** - Dynamic tiling with rich configuration
- **Sway** - i3-like lightweight option (SwayFX fork)
- Per-machine and per-user configuration overrides

### Development & DevOps

- Complete Kubernetes setup (kubectl, helm, k9s, kubeswitch)
- Podman container support with Docker compat
- Go development with $GOPATH
- NeoVim with extensive plugin ecosystem (25 plugins)
- VSCode with 32 extensions
- OpenCode AI coding assistant

### Security

- UEFI Secure Boot via Lanzaboote
- agenix for encrypted credentials
- LUKS disk encryption support
- LVM for flexible storage management
- Custom CA certificates
- nftables firewall (per-machine opt-in)
- ClamAV antivirus (per-machine opt-in)
- Kernel sysctl hardening (dmesg_restrict, kptr_restrict, ptrace scope, etc.)

### Networking & VPN

- Tailscale mesh VPN with route-conflict workarounds
- NetBird WireGuard VPN
- OpenVPN support
- SSH configuration management

### Remote & Collaboration

- Sunshine for game/desktop streaming
- Moonlight Qt remote desktop client
- KDE Connect device integration

### Modern Tools & AI

- Goji: AI-powered conventional commit messages
- OpenCode: AI coding assistant with Gemini/Anthropic
- RTK: LLM token optimization with 60-90% reduction on dev commands
- Atuin: Shell history sync and search
- Pre-commit hooks for code quality
- Treefmt for code formatting
- Difftastic for enhanced diffs

## CI/CD Pipeline

**GitHub Actions Workflows (2 files):**

- `build.yaml` - Build all 4 profiles (totoro, anya, nishinoya, tanjiro) via matrix strategy on push/PR to main. Self-hosted runner, Cachix/install-nix, S3 cache auth, 120min timeout.
- `npins-update.yaml` - Automated dependency updates every 6 hours or manual dispatch. Updates each pin independently (max 10 parallel), syncs devenv.yaml nixpkgs revision, creates PRs with auto-merge.

**Features:**

- Self-hosted runner support
- Cachix caching integration
- Custom S3 cache (didactiklabs-nixcache / nix-cache)
- Matrix-based multi-profile builds
- Concurrent job management with cancel-in-progress

## Installation & Usage

### Build Installation ISO

```bash
nix-build default.nix -A buildIso
```

### Deploy Configuration

```bash
colmena apply-local --sudo -v switch
```

### Development Environment

```bash
direnv allow  # Automatically loads devenv
```

**Available Scripts:**

- `hello` - Greeting message
- `build-iso` - Build installation ISO
- `test-iso` - Build and test ISO in QEMU VM with UEFI
- `generate-docs` - Auto-generate docs/MODULES.md from module definitions

### Interactive Installer

```bash
sudo installer
```

- Select disk and hostname
- Configure LUKS encryption
- Set user credentials
- Automatic Colmena deployment

## Architecture & Design

### Key Principles

1. **Declarative** - All configuration as Nix code
2. **Composable** - Mix and match features via modules
3. **Reproducible** - Pinned dependencies via npins
4. **Multi-Machine** - Single repo manages all systems
5. **Secrets-Safe** - agenix for encrypted credentials
6. **Modern** - Wayland-only, no X11
7. **Secure** - UEFI Secure Boot, kernel hardening, firewall

### Configuration Hierarchy

```
profiles/{hostname}/
  ├── configuration.nix → hive.nix → base.nix
  └── {username}/ → homeManagerModules/

nixosModules/ → base.nix
customPkgs/ → base.nix
npins/ → dependency sources
```

## Custom Packages (10 total)

| Package      | Version | Purpose                                               |
| ------------ | ------- | ----------------------------------------------------- |
| `rtk`        | v0.31.0 | CLI proxy for 60-90% LLM token reduction              |
| `ginx`       | main    | Run Nix code from git repos                           |
| `goji`       | 0.2.1   | Conventional commits with AI/emoji support            |
| `ytui`       | main    | YouTube video query and playback TUI                  |
| `jtui`       | v1.0.0  | JSON viewer TUI                                       |
| `crd-wizard` | v0.1.9  | Kubernetes CRD visualization dashboard                |
| `pvmigrate`  | v0.12.2 | Migrate PersistentVolumeClaims between StorageClasses |
| `songbird`   | v0.4.0  | Custom utility                                        |
| `witr`       | v0.3.1  | Custom utility                                        |
| `kl`         | v0.6.1  | Interactive Kubernetes log viewer (frozen)            |

## Dependencies & Pinning (26 total)

**Core Framework:**

- `nixpkgs` - Branch: nixos-unstable
- `home-manager` - Branch: master
- `agenix` (v0.15.0) - Age-based secrets management
- `disko` (v1.13.0) - Declarative disk partitioning
- `stylix` - Declarative theming system
- `niri-flake` - Niri compositor flake
- `nixvim` - NeoVim configuration framework
- `lanzaboote` (v1.0.0) - UEFI Secure Boot
- `crane` (v0.23.1) - Rust build tooling (used by lanzaboote)
- `rust-overlay` - Rust toolchain overlay (used by lanzaboote)
- `nixos-hardware` - Hardware-specific NixOS modules

**Application Sources:**

- `dms` - DankMaterialShell compositor shell
- `dms-plugin-registry` - DMS plugin registry
- `ds4drv` - DualShock 4 controller driver
- `flake-compat` - Flake compatibility layer
- `99` - ThePrimeagen's 99 NixVim plugin

**Custom Package Sources:** ginx, goji, ytui, jtui, crd-wizard, pvmigrate (frozen), rtk, songbird, witr, kl (frozen)

## Assets (39 files)

- **Certificates (3):** bealv-ca.crt, didactiklabs-ca.crt, logicmg-ca.crt
- **DMS Plugins (16 files):** vpn-dms, nixos-update, opencode-usage (widgets, settings, scripts)
- **Images (10):** wallpapers, screenshots, volume control icons
- **Kubernetes (4):** OIDC kubeconfigs (didactiklabs, bealv, bealvprod, logicmg)
- **OpenVPN (1):** bealv.ovpn
- **Rofi (5):** config, OneDark color scheme, launcher and powermenu styles
- **Sounds (2):** notifications.mp3, startup.mp3

## For AI Agents

### Important: Git Commit Policy

**AI agents MUST NEVER commit anything to this repository unless explicitly requested by the user.** This includes:

- Never creating commits automatically
- Never amending commits
- Never pushing to remote branches
- Never making any git commit operations without explicit user instruction

If you make changes, always present them for user review before committing.

### When working with this project

1. **Configuration Files** - Always start with `base.nix`, `hive.nix`, and relevant profile
2. **Module System** - Use `nixosModules/` for system features, `homeManagerModules/` for user configs
3. **Per-Machine Customization** - Override in `profiles/{hostname}/` or user subdirectories
4. **Dependencies** - Check `npins/sources.json` for versions, update via npins
5. **Custom Packages** - Add new packages to `customPkgs/`
6. **Secrets** - Use agenix for credentials in `installer/` or user configs
7. **Testing** - Use `default.nix` to build and test ISO
8. **Deployment** - Use `colmena apply-local --sudo` for local changes
9. **Git Hooks** - Configured in `devenv.nix`, run automatically on commit
10. **Documentation** - Keep `README.md` and `AGENTS.md` updated; run `generate-docs` to update `docs/MODULES.md`
11. **AGENTS.md Updates** - Always update `AGENTS.md` after making changes to project structure, adding/removing machines, modules, packages, or features. This ensures the documentation stays accurate for future AI agents.
