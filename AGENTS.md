# AI Agents Guide

## Project Overview

**Nixbook** is a production-grade, reproducible NixOS configuration repository providing declarative system management for multiple machines using the Nix programming language.

**Repository:** `git@github.com:didactiklabs/nixbook.git`
**Primary Goal:** Create a robust, reproducible NixOS environment with modern Wayland display servers and UEFI boot support.

## Key Statistics

- **Total Size:** 4.5 GB
- **Nix Files:** 132 files (~9,022 lines of code)
- **Active Machines:** 3 (totoro, anya, nishinoya)
- **Home Manager Modules:** 30+
- **NixOS Modules:** 18
- **Custom Packages:** 11

## Core Tools

- `NixOS` - Linux distribution with declarative configuration
- `Colmena` - Declarative machine deployment tool
- `npins` - Nix dependency pinning and source management
- `Home Manager` - User-level configuration management
- `agenix` - Age-based secrets management
- `Disko` - Declarative disk partitioning

## Directory Structure

### Configuration Layers

```
profiles/{hostname}/              Machine-specific configurations
  ├── configuration.nix
  ├── default.nix
  └── {username}/                 User-specific overrides

nixosModules/                     System-level modules (18 files)
homeManagerModules/               User-level modules (30+ files)
base.nix                          Core entry point
hive.nix                          Colmena deployment config
```

### Dependency & Package Management

- `npins/` - Pinned external dependencies (nixpkgs, home-manager, agenix, disko, stylix, etc.)
- `customPkgs/` - 11 custom packages (ginx, goji, ytui, jtui, crd-wizard, etc.)
- `assets/` - Static assets: themes, plugins, images, certificates, VPN configs

### Installation & Deployment

- `installer/` - Interactive NixOS installer with LUKS encryption, LVM, and Disko support
- `.github/workflows/` - GitHub Actions CI/CD for all 3 machines
- `devenv.nix/.envrc` - Development environment with direnv integration

## NixOS Modules (18 core modules)

| Module                                   | Purpose                                   |
| ---------------------------------------- | ----------------------------------------- |
| `core.nix`                               | Kernel, bootloader, systemd configuration |
| `userConfig.nix`                         | User management framework                 |
| `tools.nix`                              | Development and utility tools             |
| `hyprland.nix`, `niri.nix`, `sway.nix`   | Wayland compositor configs                |
| `greetd.nix`                             | Login manager configuration               |
| `networkManager.nix`                     | Network connectivity                      |
| `sunshine.nix`                           | Remote desktop streaming                  |
| `printTools.nix`                         | Printing and scanner support              |
| `laptopProfile.nix`                      | Laptop-specific optimizations             |
| `caCertificates.nix`                     | Custom CA certificates                    |
| `tailscale-fix.nix`, `netbird-tools.nix` | VPN clients                               |

## Home Manager Modules (30+)

**Desktop Environment & UI:**

- Hyprland, Sway, Niri window managers with configs
- Stylix declarative theming
- GTK configuration
- Font management
- Rofi launcher theming

**Terminal & Shell:**

- Zsh with plugins
- Kitty terminal emulator
- Starship prompt
- Atuin shell history sync

**Development:**

- NixVim (NeoVim in Nix) with plugins
- VSCode with 200+ extensions
- Git configuration and tools
- Kubernetes tools (k9s, kubeswitch, kubectl, helm)

**Applications:**

- Thunderbird email client
- MPV media player
- Dolphin file manager
- Fcitx5 input method framework
- DankMaterialShell (DMS) terminal UI
- Fastfetch system information

**Infrastructure:**

- Goji AI-powered conventional commit helper
- SSH configuration
- Desktop apps registry

## Machine Profiles (3 machines)

### totoro - Main Development Machine

- **Location:** `profiles/totoro/`
- **User:** khoa
- **WM:** Niri (primary with Hyprland fallback)
- **Modules:** Work tools, laptop profile
- **Configs:** Git, Hyprland, Kanshi monitors, Niri, Thunderbird

### anya - Secondary/Deployment Machine

- **Location:** `profiles/anya/`
- **User:** khoa
- **WM:** Sway (primary)
- **Modules:** Sunshine (remote desktop), work tools
- **Features:** Kubernetes setup, streaming server

### nishinoya - Tertiary Machine

- **Location:** `profiles/nishinoya/`
- **User:** aamoyel
- **WM:** Hyprland/Niri options
- **Configs:** Git, Hyprland, Kanshi monitors, Niri

## Key Features

### Desktop Environments (Wayland-only)

- **Niri** - Scrollable tiling compositor (preferred)
- **Hyprland** - Dynamic tiling with rich configuration
- **Sway** - i3-like lightweight option
- Per-machine and per-user configuration overrides

### Development & DevOps

- Complete Kubernetes setup (kubectl, helm, k9s, kubeswitch)
- Docker container support
- Go development with $GOPATH
- NeoVim with extensive plugin ecosystem
- VSCode with 200+ extensions

### Secrets & Security

- agenix for encrypted credentials
- LUKS disk encryption support
- LVM for flexible storage management
- Custom CA certificates
- VPN options (Tailscale, NetBird)

### Remote & Collaboration

- Sunshine for game/desktop streaming
- Tailscale mesh VPN integration
- NetBird VPN client
- SSH configuration management

### Modern Tools & AI

- Goji: AI-powered conventional commit messages
- Atuin: Shell history sync and search
- Pre-commit hooks for code quality
- Treefmt for code formatting
- Difftastic for enhanced diffs

## CI/CD Pipeline

**GitHub Actions Workflows:**

- `build-totoro.yaml` - Build & validate totoro configuration
- `build-anya.yaml` - Build & validate anya configuration
- `build-nishinoya.yaml` - Build & validate nishinoya configuration
- `npins-update.yaml` - Automated dependency updates

**Features:**

- Self-hosted runner support
- Cachix caching integration
- Custom S3 cache (didactiklabs-nixcache)
- nixfmt formatting checks
- Concurrent job management

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

### Configuration Hierarchy

```
profiles/{hostname}/
  ├── configuration.nix → hive.nix → base.nix
  └── {username}/ → homeManagerModules/

nixosModules/ → base.nix
customPkgs/ → base.nix
npins/ → dependency sources
```

## Custom Packages (11 total)

| Package                           | Purpose                     |
| --------------------------------- | --------------------------- |
| `ginx`                            | Run Nix code from git repos |
| `goji`                            | Conventional commit with AI |
| `ytui`                            | YouTube terminal UI         |
| `jtui`                            | JSON viewer TUI             |
| `crd-wizard`                      | Kubernetes CRD wizard       |
| `pvmigrate`                       | Proxmox VM migration        |
| `okada`, `songbird`, `witr`, `kl` | Custom utilities            |

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
10. **Documentation** - Keep `README.md` and `AGENTS.md` updated
11. **AGENTS.md Updates** - Always update `AGENTS.md` after making changes to project structure, adding/removing machines, modules, packages, or features. This ensures the documentation stays accurate for future AI agents.
