# Introduction

**Nixbook** is a personal, declarative NixOS configuration repository that manages several machines from a single source of truth. The whole system state — bootloader, kernel, drivers, display server, user environments, secrets and services — is Nix code, versioned in Git.

It ships:

- modern **Wayland** compositors ([Niri](/desktop/niri) and [SwayFX](/desktop/sway)) with a choice of desktop shell ([DankMaterialShell](/desktop/dms) or nixbook's own [nixbook-shell](/nixbook-shell/));
- a fully featured **Zsh** shell with GNU CLI replacements, a complete **development and Kubernetes toolchain**, and NixVim;
- **per-machine profiles** selected automatically by hostname;
- **security** as a first-class concern: UEFI Secure Boot (Lanzaboote), LUKS disk encryption, agenix-managed secrets and kernel hardening;
- **deployment** with Colmena, dependency pinning with npins, and a custom interactive **installer ISO**.

::: info Wayland and UEFI only
Nixbook supports Wayland sessions with UEFI boot only. Legacy BIOS and X11 sessions are not supported (X11 apps run through XWayland).
:::

## Goals

The primary goal is a personal, highly customisable and reproducible NixOS environment that manages a whole fleet of machines from one version-controlled repository. Rather than configuring each system by hand, the complete system state is declarative code.

Nixbook offers an opinionated base configuration designed to be **extended rather than rewritten**. Shared functionality lives in reusable NixOS and Home Manager modules, each with opt-in/opt-out options, so features such as gaming support, sim-racing hardware, VPNs, printing or Secure Boot can be toggled per machine without duplicating code. Machine-specific behaviour lives in per-hostname [profiles](/machines/profiles), refined further with per-user overrides.

This yields:

| Benefit                  | How                                                                                                        |
| ------------------------ | ---------------------------------------------------------------------------------------------------------- |
| **Reproducibility**      | Pinned dependencies (npins): the same commit builds the same system on any machine, at any time.           |
| **Composability**        | Modules are mixed and matched; a new machine is assembled from existing building blocks.                   |
| **Consistency**          | Shell, editor, theming and dev toolchain are identical everywhere — no configuration drift.                |
| **Maintainability**      | A change in a shared module reaches every machine importing it; updates are atomic and can be rolled back. |
| **Safe experimentation** | Changes are reviewed, tested (in CI, or in a VM) and reverted like any other code.                         |

Provisioning a brand-new laptop is as simple as choosing a profile and running a single deployment command, with the assurance that the result matches every other machine built from the same configuration.

## Design principles

1. **Declarative** — all configuration is Nix code.
2. **Composable** — features are modules you switch on.
3. **Reproducible** — every input is pinned with npins.
4. **Multi-machine** — one repository manages every system.
5. **Secrets-safe** — credentials are encrypted with agenix.
6. **Modern** — Wayland-only.
7. **Secure** — Secure Boot, kernel hardening, firewall.

## Core tools

| Tool                                                          | Role                                        |
| ------------------------------------------------------------- | ------------------------------------------- |
| [NixOS](https://nixos.org)                                    | Linux distribution with declarative config  |
| [Home Manager](https://github.com/nix-community/home-manager) | User-level configuration                    |
| [Colmena](https://github.com/zhaofengli/colmena)              | Declarative deployment (local, no SSH)      |
| [npins](https://github.com/andir/npins)                       | Dependency pinning, no flakes required      |
| [agenix](https://github.com/ryantm/agenix)                    | Age-encrypted secrets                       |
| [Disko](https://github.com/nix-community/disko)               | Declarative disk partitioning (installer)   |
| [Lanzaboote](https://github.com/nix-community/lanzaboote)     | UEFI Secure Boot                            |
| [Stylix](https://github.com/danth/stylix)                     | System-wide theming                         |
| [devenv](https://devenv.sh)                                   | Development environment, git hooks, scripts |

## Where to go next

- New here? Read the [architecture](./architecture) to understand how the pieces fit.
- Setting up a machine? Head to [Installation](/installation/).
- Looking for a specific option? See the [module options reference](/reference/options).
- Want the shortcuts? See [keybindings](/desktop/keybindings).

## Screenshots

Niri with the desktop shell:

![Niri configuration](https://raw.githubusercontent.com/didactiklabs/nixbook/main/assets/images/screenshot.png)

Headless Sunshine/Moonlight remote desktop:

![Sunshine/Moonlight v1](https://raw.githubusercontent.com/didactiklabs/nixbook/main/assets/images/screenshot-demo-sunshine.png)

Sunshine/Moonlight streamed to a Windows client:

![Sunshine/Moonlight on Windows](https://raw.githubusercontent.com/didactiklabs/nixbook/main/assets/images/screenshot-demo-sunshine-windows.png)
