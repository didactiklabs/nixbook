# Settings

nixbook-shell's settings live in `~/.config/nixbook-shell/config.json` and are edited from its **Settings window** — or pinned from Nix. The rule is simple:

> **Every key set in Nix is locked; every other key stays editable.**

## The Settings window

Open it with **Mod+Escape**, the sidebar's settings button, the _Shell settings_ launcher entry, or `nixbook-shell ipc call settings toggle`. It is a normal application window (move, resize, tile, close with Mod+Q).

Pages are grouped as:

| Group           | Pages                                                                   |
| --------------- | ----------------------------------------------------------------------- |
| **Personalize** | Quick, Appearance, Desktop, Bar                                         |
| **Shell**       | Panels, Lock screen, Desktop agents, Window layouts                     |
| **System**      | General, Services, Niri                                                 |
| —               | Profile (the card at the top), About, and a shortcut to the config file |

- **Ctrl+F** searches every setting and section on every page and scrolls to it.
- Notification rules live on the **Bar** page (_Notifications_ section); AI and update settings on **Services**.
- Settings pinned in Nix show a **red lock** and are disabled. A header toggle, _Editable only_, hides them.

## Setting values from Nix

```nix
# nixbook: profiles/<host>/<user>/…
customHomeManagerModules.nixbookShellConfig.settings = {
  appearance.theme = "chiikawa";
  appearance.chiikawa.variant = "usagi";
  bar.bottom = true;
  background.screenList = [ "eDP-1" ];
};

# standalone: programs.nixbook-shell.settings = { … };
```

- The options are **generated from the shell's built-in defaults** (`builtin-defaults.json`), each typed from its default value: a misspelt key or a wrong type **fails evaluation** (`The option '…settings.bar.bottomm' does not exist`).
- Only keys you set are applied, on every activation, over the live file (Nix wins). Keys you don't set keep their built-in default or whatever you chose in the Settings window, across restarts, reboots and switches.
- **Delete a key in Nix and it unlocks**: the lock list is generated from your Nix configuration, and the running shell reloads it on activation.
- Desktop widget positions and similar runtime state are deliberately not Nix options: arrange them in the shell.

nixbook's shared values (`homeManagerModules/nixbookShellConfig/settings.nix`) are applied as defaults, so a profile overrides them key by key. They include, for example, 15-second notification popups, a dock with pinned apps, the update repository URL, notification rules (keep chat apps on screen, quiet duplicated calendar reminders), and two guards that keep the wallpaper palette from fighting Stylix in terminals.

## The `config` CLI

Turn what you clicked into Nix:

```bash
nixbook-shell config diff      # settings changed in the window, as Nix lines to paste
nixbook-shell config pinned    # the keys locked by Nix
nixbook-shell config dump      # every non-default value, as a Nix attribute set
nixbook-shell config path      # where the files are
```

A typical workflow: experiment in the Settings window, run `nixbook-shell config diff`, and paste the result into your profile to make it permanent on every machine.

## Removed and renamed settings

Settings that did nothing were removed; an old Nix configuration that still sets one evaluates with a **warning** and the value is ignored. Renamed settings are migrated — e.g. the former `appearance.persona.enable = true` becomes `appearance.theme = "persona"` (with a deprecation warning in Nix).
