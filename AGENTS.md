# AI Agents Guide

## Project Overview

**Nixbook** is a production-grade, reproducible NixOS configuration repository providing declarative system management for multiple machines using the Nix programming language.

**Repository:** `git@github.com:didactiklabs/nixbook.git`
**Primary Goal:** Create a robust, reproducible NixOS environment with modern Wayland display servers and UEFI boot support.

## Key Statistics

- **Total Size:** 4.5 GB
- **Nix Files:** 133 files (~9,837 lines of code)
- **Active Machines:** 3 (totoro, anya, nishinoya)
- **Home Manager Modules:** 34 (21 main files + 13 plugin/config subdirectories)
- **NixOS Modules:** 16 files
- **Custom Packages:** 11
- **CI/CD Workflows:** 4
- **NixVim Plugins:** 25
- **VSCode Extensions:** 200+
- **Pinned Dependencies:** 35+

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

## NixOS Modules (16 files)

| Module               | Lines | Purpose                                                          |
| -------------------- | ----- | ---------------------------------------------------------------- |
| `userConfig.nix`     | 209   | User management framework with mkUser helper                     |
| `core.nix`           | 201   | Bootloader (systemd-boot), kernel settings, systemd services     |
| `tools.nix`          | 109   | Development and utility tools (git, direnv, treefmt, pre-commit) |
| `niri.nix`           | 61    | Niri scrollable tiling compositor setup                          |
| `tailscale-fix.nix`  | 60    | Tailscale VPN workaround/fixes                                   |
| `greetd.nix`         | 57    | Login manager (greeter configuration)                            |
| `caCertificates.nix` | 56    | Custom CA certificates (bealv, didactiklabs, logicmg)            |
| `getRevision.nix`    | 54    | Git revision tracking for system                                 |
| `networkManager.nix` | 41    | Network connectivity and wifi management                         |
| `netbird-tools.nix`  | 41    | NetBird VPN client setup                                         |
| `sunshine.nix`       | 39    | Remote desktop streaming configuration                           |
| `hyprland.nix`       | 39    | Hyprland dynamic tiling compositor                               |
| `laptopProfile.nix`  | 38    | Laptop-specific: power management, display scaling               |
| `printTools.nix`     | 37    | Printing and scanner support (CUPS, SANE)                        |
| `sway.nix`           | 27    | Sway i3-like tiling compositor                                   |
| `default.nix`        | 19    | Module imports aggregator                                        |

## Home Manager Modules (34 files/subdirectories)

**Core User Configuration:**

- `entrypoint.nix` - Profile validation and MIME defaults
- `commonShellConfig.nix` (118 LOC) - Shared shell environment
- `zshConfig.nix` (80 LOC) - Zsh with fast-syntax-highlighting, autopair
- `gitConfig.nix` (125 LOC) - Git configuration with user-specific overrides

**Terminal & Shell:**

- `kittyConfig.nix` (122 LOC) - Terminal emulator with themes
- `starshipConfig.nix` (110 LOC) - Prompt with git info and nix integration
- `atuinConfig.nix` - Shell history sync (per-environment support)
- `cliTools.nix` - CLI utilities (bat, eza, ripgrep, etc.)

**Desktop Environments:**

- `hyprland/` - Hyprland compositor (9,239 LOC config + 4,535 LOC lock)
- `niri/` - Niri scrollable compositor (20,654 LOC config)
- `sway/` - Sway i3-like compositor (14,772 LOC config)
- `gtkConfig.nix` (72 LOC) - GTK appearance and theming
- `fontConfig.nix` (46 LOC) - Font management
- `stylixConfig.nix` (44 LOC) - Declarative theming system
- Rofi launcher with OneDark color scheme

**Development:**

- `devTools.nix` (58 LOC) - Languages and dev tools
- `goji.nix` (236 LOC) - AI-powered conventional commits
- `nixvim/` - NeoVim with 25 plugins (LSP, Treesitter, Telescope, neo-tree, etc.)

**Kubernetes & DevOps:**

- `k9sConfig.nix` (336 LOC) - K9s dashboard configuration
- `kubeTools.nix` (97 LOC) - kubectl, helm, kubeswitch, k9s setup
- `kubeswitchConfig.nix` (41 LOC) - Kubernetes context switcher

**Applications:**

- `dmsConfig.nix` (191 LOC) - DankMaterialShell (DMS) terminal UI
- `fastfetchConfig.nix` (152 LOC) - System information display
- `desktopApps.nix` (37 LOC) - Firefox, Dolphin, MPV setup
- `dolphinConfig.nix` - File manager configuration
- `mpvConfig.nix` - Media player configuration
- `thunderbirdConfig.nix` - Email client configuration

**Infrastructure & Tools:**

- `fcitx5Config.nix` (53 LOC) - Input method framework (CJK support)
- `rtkConfig.nix` - RTK (Rust Token Killer) CLI proxy for LLM token optimization
- `sshConfig.nix` - SSH key management
- `vscode/` - VSCode with 200+ extensions (8,170 LOC default.nix + 5,400 LOC extensions list)
- `scripts/` - Custom shell scripts (volume.nix: 6,398 LOC sophisticated volume control)

## Machine Profiles (3 machines)

### totoro - Main Development Machine

- **Location:** `profiles/totoro/`
- **User:** khoa
- **Primary WM:** Niri (with Hyprland fallback)
- **Modules:** laptopProfile, networkManager, greetd, niri, caCertificates
- **Special Features:** Dual monitor setup (kanshiConfig), Go development environment
- **Work Environments:** didactiklabs, bealv kubeconfigs
- **Home Manager Modules:** cliTools, devTools, fontConfig, gitConfig, gtkConfig, sshConfig, starship, niriConfig, fastfetchConfig, desktopApps, kubeTools, nixvimConfig, gojiConfig, atuinConfig, kittyConfig, zshConfig, kubeswitchConfig, fcitx5Config, thunderbirdConfig, rtkConfig (with auto-rewrite hook), dmsConfig

### anya - Secondary/Deployment Machine (Gaming/Streaming)

- **Location:** `profiles/anya/`
- **User:** khoa
- **Primary WM:** Sway
- **Modules:** networkManager, sunshine, sway, caCertificates
- **Special Features:** Wake-on-LAN, Steam Big Picture auto-launch, Proton GE, Immich photo sync timers
- **Work Environments:** didactiklabs, bealv kubeconfigs
- **Home Manager Modules:** cliTools, devTools, fontConfig, gitConfig, gtkConfig, securityTools, sshConfig, starship, swayConfig, systemTools, nixvimConfig, fastfetchConfig, atuinConfig, kittyConfig, zshConfig, dmsConfig

### nishinoya - Tertiary Machine

- **Location:** `profiles/nishinoya/`
- **User:** aamoyel
- **Primary WM:** Niri (with Hyprland fallback)
- **Modules:** laptopProfile, networkManager, greetd, niri, caCertificates
- **Special Features:** Unprivileged port access, Yubico security key lock on removal
- **Work Environments:** didactiklabs, logicmg kubeconfigs
- **Extra Packages:** Google Chrome, Bitwarden, GitKraken, Google Cloud SDK, Slack, Kanidm
- **Home Manager Modules:** cliTools, devTools, fontConfig, gitConfig, gtkConfig, sshConfig, starship, niriConfig, fastfetchConfig, desktopApps, vscode, kubeTools, nixvimConfig, gojiConfig, atuinConfig, kittyConfig, zshConfig, kubeswitchConfig, fcitx5Config, dmsConfig

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
- RTK: LLM token optimization with 60-90% reduction on dev commands
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

## Custom Packages (12 total)

| Package      | Purpose                                            |
| ------------ | -------------------------------------------------- |
| `rtk`        | CLI proxy for 60-90% LLM token reduction (v0.29.0) |
| `ginx`       | Run Nix code from git repos                        |
| `goji`       | Conventional commits with AI/emoji support         |
| `ytui`       | YouTube video query and playback TUI               |
| `jtui`       | JSON viewer TUI (v1.0.0)                           |
| `crd-wizard` | Kubernetes CRD visualization dashboard (v0.1.9)    |
| `pvmigrate`  | Proxmox VM migration tool (v0.12.2)                |
| `okada`      | Custom utility (v0.0.1)                            |
| `songbird`   | Custom utility (v0.4.0)                            |
| `witr`       | Custom utility (v0.3.0)                            |
| `kl`         | Custom utility (v0.6.1, frozen)                    |
| `99`         | Custom utility                                     |

## Dependencies & Pinning

**Core Framework:**

- `nixpkgs` - Branch: nixos-unstable
- `home-manager` - Master branch
- `agenix` (v0.15.0) - Age-based secrets management
- `disko` (v1.13.0) - Declarative disk partitioning
- `stylix` - Declarative theming system
- `niri-flake` - Niri compositor flake

**Pinned Dependencies:** 35+ packages managed via `npins/sources.json`

## CI/CD Pipeline

**GitHub Actions Workflows (4 total):**

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

## Assets

**Includes (32 files):**

- Custom CA certificates (bealv, didactiklabs, logicmg)
- DMS plugins with custom widgets
- System and theme images (wallpapers, volume control icons)
- Rofi launcher theme (OneDark color scheme)
- Kubernetes kubeconfigs (OIDC-based for 4 environments)
- VPN configuration (bealv.ovpn)
- Audio files (notification and startup sounds)

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
