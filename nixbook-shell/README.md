# nixbook-shell

A Quickshell (QML) desktop shell for niri and Hyprland: bar, dock, sidebars,
launcher, notifications, lock screen, desktop widgets, an AI chat and the
optional Persona style (the Persona art direction rendered with Material 3
manners: rounded corners with the Persona cut, soft accent glow, tonal
surfaces). It started as a fork of
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
- `nixosModules.default` — optional, on NixOS: lets the assistant know the
  system's toggles (`nixos-module.nix`, see below)
- `lib` — the settings helpers (`lib.nix`)

The shell runs as the `nixbook-shell` user service. Bind keys to
`nixbook-shell ipc call <target> <function>` to open its panels
(`search toggle`, `sidebarLeft toggle`, `sidebarRight toggle`,
`settings toggle`, `lock activate`, …).

## Login screen and loading screen

On NixOS, `nixbook-shell.greeter` (`greeter.nix`, part of
`nixosModules.default`) makes the login screen match the shell: greetd with
[ReGreet](https://github.com/rharish101/ReGreet) in cage, themed from one
user's live settings — the Material palette generated from the wallpaper, or
the Persona style in its variant — and showing the login screen wallpaper.

```nix
nixbook-shell.greeter = {
  enable = true;
  user = "alice";               # whose shell settings it follows
  background = ./login.jpg;     # optional: default login screen wallpaper
};
```

The Settings menu (Background > Wallpaper) sets the desktop, lock screen
(`background.lockWall`) and login screen (`background.greeterWall`, shown when
the greeter is enabled for this user) wallpapers separately; an empty one
falls back to the lock screen's, then the desktop's. Both can also be set in
Nix through `programs.nixbook-shell.settings.background`. The
`nixbook-shell-greeter-theme` service renders the theme into
`/var/lib/nixbook-shell-greeter` as that user whenever the settings or palette
change (`scripts/greeter-theme.sh`, Persona colours read from
`Persona.qml` by `scripts/persona-palettes.py`); before its first run the
greeter uses the same theme built from the settings set in Nix.
Authentication is greetd's PAM service: ReGreet shows and answers PAM's
messages, so security keys (pam_u2f's cue) and fingerprints work.

With niri installed the greeter runs in niri (`compositor`), which shows the
theme's colour and the wallpaper from its first frames, and it takes the
plymouth splash over without clearing the screen; cage is the fallback.

After login, `nixbook-shell splash` (the `nixbook-shell-splash` user service,
`splash.enable`) shows the shell's loading screen (`src/earlySplash.qml`,
drawing the same `BootSplashArt` as the shell's own BootSplash) from the
start of the session until the shell's BootSplash is up, then fades out: no
black screen or half-drawn desktop in between.

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
`niriConfig`, `nixvim`). When nixvim's Home Manager module is enabled,
`assistant.nixvim` defaults to its evaluated keymaps (`keymaps`,
`keymapsOnEvents`, `lsp.keymaps`, `files.<name>.keymaps`) and leader, so the
config assistant lists them ("all vim shortcuts") and looks them up ("what does
<leader>ff do in vim?") as Neovim really gets them, overrides included.

The config assistant also answers basic questions about the system, all read
from the evaluated configuration: NixOS release, kernel, host, time zone,
locale, keyboard layout, bootloader, shell, editor, Nix (`assistant.os`), and
"is X enabled?" for every option set with a real `enable` option, discovered
from the module system's options trees (`toggles.nix`: declared, bool, visible,
so renamed and removed options are never read). Home Manager's come from its
own options; NixOS's need `nixosModules.default`, since Home Manager modules
only get the NixOS configuration, not its options. "How do I update / roll
back / free disk space…" answers (`assistant.howTo`) are generic NixOS ones by
default; set one by name to your configuration's own way (a deploy tool, an
update script), or to null to drop it.

With a model selected in the chat, all of this is only reference for the
model's system prompt: it answers with its own knowledge too, and says when it
isn't sure.

## Layout

| Path               | What                                                                               |
| ------------------ | ---------------------------------------------------------------------------------- |
| `default.nix`      | entry point (`package`, `homeManagerModules.default`, `lib`)                       |
| `package.nix`      | the launcher: runtime `PATH`, QML import path, `config` CLI                        |
| `qml.nix`          | the QML tree as installed (store-path fixups, Persona art)                         |
| `quickshell.nix`   | Quickshell from `quickshellSrc` plus `patches/`                                    |
| `lib.nix`          | typed settings options generated from `builtin-defaults.json`                      |
| `hm-module.nix`    | the Home Manager module `programs.nixbook-shell`                                   |
| `nixos-module.nix` | optional NixOS module: the system's toggles for the assistant                      |
| `greeter.nix`      | the login screen (`nixbook-shell.greeter`, imported by it)                         |
| `toggles.nix`      | discovers the `enable` toggles from an options tree                                |
| `scripts/`         | `config` CLI, its jq library, assistant facts, Anthropic usage, login screen theme |
| `npins/`           | default nixpkgs and quickshell pins                                                |
| `src/`             | the vendored QML tree (edited in place)                                            |
| `tests/`           | script tests, lib unit tests, the self-containment check                           |

## Tests

```sh
bash tests/scripts.sh
nix-instantiate --eval --strict --json --expr 'import ./tests/lib.nix { }'   # []
nix-instantiate --eval --strict --read-write-mode tests/standalone.nix \
  --arg homeManager '<home-manager checkout>'                                  # "ok"
```
