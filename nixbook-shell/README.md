# nixbook-shell

A Quickshell (QML) desktop shell for niri and Hyprland: bar, dock, sidebars,
launcher, notifications, lock screen, desktop widgets, an AI chat and the
optional Persona style. It started as a fork of
[pctrade/end4-pC](https://github.com/pctrade/end4-pC), itself a fork of end-4's
illogical-impulse, and is maintained here as a hard fork (credits and licence
in `src/`).

This directory is self-contained: nothing in it refers to the rest of the
nixbook repository, so it can be used on its own (nixbook's
`tests/repo.nix` checks that by evaluating a copy of it alone).

## Use

```nix
# Home Manager configuration
{ pkgs, ... }:
{
  imports = [ ./nixbook-shell/hm-module.nix ];

  programs.nixbook-shell = {
    enable = true;
    settings = {
      bar.bottom = true;
      appearance.persona.enable = true;
    };
  };
}
```

`import ./nixbook-shell { }` (or `{ inherit pkgs; }`, and `quickshellSrc` for
another quickshell pin) gives:

- `package` — the `nixbook-shell` launcher
- `homeManagerModules.default` — the module above (`hm-module.nix`)
- `lib` — the settings helpers (`lib.nix`)

The shell runs as the `nixbook-shell` user service. Bind keys to
`nixbook-shell ipc call <target> <function>` to open its panels
(`search toggle`, `sidebarLeft toggle`, `sidebarRight toggle`,
`settings toggle`, `lock activate`, …).

## Settings

Settings live in `~/.config/nixbook-shell/config.json` and are edited from the
shell's Settings window. Every key set in `programs.nixbook-shell.settings` is
applied on each activation and **locked** in that window; every other key stays
editable there. The options are generated from the built-in defaults
(`builtin-defaults.json`), so a misspelt key fails evaluation.

- `nixbook-shell config diff` — settings changed from the menu, as Nix lines
- `nixbook-shell config pinned` — the keys set in Nix
- `nixbook-shell config builtin > builtin-defaults.json` — regenerate the
  defaults after changing `src/modules/common/Config.qml`

The bar's update indicator compares `/etc/nixos/version` (JSON `{rev, branch}`)
with `updates.repoUrl`; it stays idle while that is empty (the default).

The AI chat and the config assistant can be told about the machine through
`programs.nixbook-shell.assistant` (`context`, `coreFacts`, `modules`,
`niriConfig`).

## Layout

| Path             | What                                                           |
| ---------------- | -------------------------------------------------------------- |
| `default.nix`    | entry point (`package`, `homeManagerModules.default`, `lib`)   |
| `package.nix`    | the launcher: runtime `PATH`, QML import path, `config` CLI    |
| `qml.nix`        | the QML tree as installed (store-path fixups, Persona art)     |
| `quickshell.nix` | Quickshell from `quickshellSrc` plus `patches/`                |
| `lib.nix`        | typed settings options generated from `builtin-defaults.json`  |
| `hm-module.nix`  | the Home Manager module `programs.nixbook-shell`               |
| `scripts/`       | `config` CLI, its jq library, assistant facts, Anthropic usage |
| `npins/`         | default nixpkgs and quickshell pins                            |
| `src/`           | the vendored QML tree (edited in place)                        |
| `tests/`         | script tests, lib unit tests, the self-containment check       |

## Tests

```sh
bash tests/scripts.sh
nix-instantiate --eval --strict --json --expr 'import ./tests/lib.nix { }'   # []
nix-instantiate --eval --strict --read-write-mode tests/standalone.nix \
  --arg homeManager '<home-manager checkout>'                                  # "ok"
```
