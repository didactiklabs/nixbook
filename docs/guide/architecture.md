# Architecture

Nixbook is plain Nix (no flakes): `npins` pins every input, `hive.nix` declares the machines for Colmena, and each machine's profile imports the shared modules it needs.

## Repository layout

```
nixbook/
├── hive.nix                 Colmena hive: one node per machine
├── base.nix                 Common NixOS entry point imported by every profile
├── default.nix              ISO / test-VM build targets
├── profiles/{hostname}/     Machine-specific configuration
│   ├── configuration.nix    → base.nix with the hostname
│   ├── default.nix          Hardware, enabled NixOS modules, users
│   └── {username}/          Per-user Home Manager overrides
├── nixosModules/            System-level modules  (customNixOSModules.*)
├── homeManagerModules/      User-level modules    (customHomeManagerModules.*)
├── nixbook-shell/           Standalone Quickshell desktop shell (package + modules)
├── customPkgs/              Packages not in nixpkgs (pkgs.customPkgs.<name>)
├── lib/                     pkgs.nix, overlays.nix, userConfig.nix (mkUser)
├── installer/               Interactive installer ISO and first-boot bootstrap
├── assets/                  Certificates, kubeconfigs, wallpapers, DMS plugins…
├── npins/                   Pinned sources (sources.json)
├── tests/                   Cheap regression checks (tests/run.sh)
├── docs/                    This website + generated MODULES.md
├── devenvModules/           Shared devenv module (also used by other repos)
├── devenv.nix / devenv.yaml Development environment
└── .github/workflows/       CI/CD
```

## How a machine is evaluated

```
hive.nix ── node "totoro" ──▶ profiles/totoro/configuration.nix
                                    │
                                    ▼
                                base.nix
                 ┌──────────────────┼────────────────────────────┐
                 ▼                  ▼                            ▼
   /etc/nixos/hardware-     nixosModules/ (all modules,    profiles/totoro/
   configuration.nix        off unless enabled)            default.nix
                                                               │
                                       ┌───────────────────────┴───────┐
                                       ▼                               ▼
                         customNixOSModules.* = …         userConfig.mkUser {
                         hardware, extra packages           username = "khoa";
                                                            userImports = [ ./khoa ];
                                                          }
                                                               │
                                                               ▼
                                         Home Manager: homeManagerModules/ +
                                         profiles/totoro/khoa/ (customHomeManagerModules.* = …)
```

1. **`hive.nix`** declares one Colmena node per machine. Every node allows local deployment (`colmena apply-local`), builds on the target and imports `profiles/<hostname>/configuration.nix`.
2. **`profiles/<hostname>/configuration.nix`** derives the hostname from its directory name and imports `base.nix` with it.
3. **`base.nix`** imports the machine's hardware configuration (`/etc/nixos/hardware-configuration.nix`), every module in `nixosModules/`, Home Manager, agenix and Lanzaboote, then the host profile. An optional `/etc/nixos/extraConfiguration.nix` is imported too when present, for machine-local tweaks that should not live in Git.
4. **The profile** (`profiles/<hostname>/default.nix`) switches modules on (`customNixOSModules.<module>.enable = true`), sets hardware options, and creates its users with `mkUser`.
5. **`lib/userConfig.nix` → `mkUser`** creates the account (Zsh shell, standard groups, passwordless `colmena` through sudo), and its Home Manager configuration: the external modules (Stylix, NixVim, agenix, DMS, Zen Browser), every module in `homeManagerModules/`, and the per-user directory (`profiles/<hostname>/<username>/`) where `customHomeManagerModules.*` are switched on.

## One nixpkgs instance

`lib/pkgs.nix` builds **the** nixpkgs instance — from the npins `nixpkgs` pin, with nixbook's overlays (`lib/overlays.nix`) and custom packages (`customPkgs/`, exposed as `pkgs.customPkgs.<name>`). The machines, the tests and the docs generator all use it, and `base.nix` hands it to NixOS (`nixpkgs.pkgs`), so the system is evaluated once with one instance.

::: tip
Add nixpkgs config and overlays in `lib/pkgs.nix` and `lib/overlays.nix`, not through the `nixpkgs.*` NixOS options — those are forced empty.
:::

## Modules: opt-in everywhere

Every module declares an `enable` option under one of two namespaces:

- **`customNixOSModules.<name>`** — system modules in `nixosModules/` ([System](/system/core) section);
- **`customHomeManagerModules.<name>`** — user modules in `homeManagerModules/` ([User](/user/shell) section).

A few foundational modules (`core`, `tools`, `getRevision`, `netbird-tools`, `tailscale`, `bluetoothAutoConnect` when Bluetooth is on…) are enabled by default; most others are off until a profile turns them on. The [module options reference](/reference/options) lists every option with its type, default and description — it is generated from the modules themselves.

## Configuration hierarchy

From most general to most specific, later layers override earlier ones:

1. Module defaults (`nixosModules/`, `homeManagerModules/`).
2. Shared settings (e.g. `homeManagerModules/nixbookShellConfig/settings.nix`, applied as `mkDefault`).
3. The machine profile (`profiles/<hostname>/default.nix`).
4. The user's directory in the profile (`profiles/<hostname>/<user>/`).
5. Machine-local `/etc/nixos/extraConfiguration.nix` (not in Git).

## Version stamping

The `getRevision` module writes `/etc/nixos/version` at build time — a JSON document with the Git remote, branch, commit, commit date and whether the tree was dirty — so you can always tell which commit a machine runs (`jq . /etc/nixos/version`). The update widgets of both desktop shells compare it with the remote `main` to show when an update is available.
