# nixbook-shell

A Quickshell (QML) desktop shell for niri and Hyprland: bar, dock, sidebars,
launcher, notifications, lock screen, desktop widgets, an AI chat and a choice
of themes (see [Themes](#themes)): Material, the default (colours from the
wallpaper, Material 3 tonal elevation: surfaces are told apart by their tone
and a thin outline, with no shadows); Persona (Persona 5 Royal by default:
slanted black panels with bold Royal gold outlines, hard unblurred red offset
shadows, red accent slashes and halftone art); and Chiikawa (pastel light
palettes, bubbly corners, bouncy motion and the characters themselves). None
blurs a shadow, which keeps them light on integrated GPUs. It started as a
fork of
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
      appearance.theme = "persona";
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
`nixosModules.default`) makes the login screen the shell's own: greetd running
`nixbook-shell greeter` (`src/greeter.qml`, `modules/ii/greeter/`, Quickshell's
greetd client) with one user's look — the theme and variant, the palette
(the theme's, or the one generated from the wallpaper), fonts, account picture
and cursor — around a login card: the user (arrows switch between the
machine's accounts), the password, PAM's cues (security key, fingerprint,
further prompts such as a one-time code) and the session to start, which it
remembers (`/var/cache/nixbook-shell-greeter`), with suspend, reboot and power
off in the corner.

```nix
nixbook-shell.greeter = {
  enable = true;
  user = "alice";               # whose look it follows (null: the default look)
  cursorUser = "alice";         # whose cursor it shows (default: `user`)
  background = ./login.jpg;     # optional: default login screen wallpaper
};
```

The Settings menu (Background > Wallpaper, Appearance > Theme for each
variant) sets the desktop, lock screen (`background.lockWall`) and login
screen (`background.greeterWall`, shown when the greeter is enabled for this
user) wallpapers; an empty one falls back to the lock screen's, then the
desktop's. The greeter can't read the home directory: the
`nixbook-shell-greeter-theme` service exports what it needs into
`/var/lib/nixbook-shell-greeter` as that user whenever the settings or palette
change (`scripts/greeter-theme.sh`: the look's settings only, the palette's
colours, the account picture and the wallpaper, copied); before its first run
the greeter uses the settings set in Nix.

With niri installed the greeter runs in niri (`compositor`), which shows the
theme's colour and the wallpaper from its first frames, and it takes the
plymouth splash over without clearing the screen; cage is the fallback, and
tuigreet takes over if neither starts, so there is always a login prompt.

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

### Calendars and to-do list

[DankCalendar](https://github.com/AvengeMedia/dankcalendar) (`dcal`) is part of
the shell (`dankcalendar.nix`, on its PATH; its daemon is the `dcal` user
service) and keeps every calendar surface in sync:

- events: dots on the days of the sidebar, desktop and bar clock calendars,
  the next events in the bar clock popup, a day's events when you click it in
  the sidebar (with an "add event" button); clicking the bar clock (right
  click: sync) or a day of the desktop calendar opens DankCalendar. The
  shell rereads them every `calendar.refreshMinutes` (30), keeping the same
  data (no redraw) when nothing changed; the refresh button in the sidebar
  calendar's header syncs the accounts now;
- the next events: the "Next Event" bar widget (`nextEvent` in a bar layout:
  "in 12 min" and the title, the following ones on hover; click joins the
  meeting when it starts within 10 minutes, else opens DankCalendar) and
  desktop widget (`background.widgets.nextEvent`: the next one large with a
  Join button, the three after it);
- tasks: the to-do list (sidebar, desktop widget, bar clock popup, the
  launcher's "add task") is the account's task list (Google Tasks…) once one
  is connected, a local list before that (`src/services/Todo.qml`);
- reminders: DankCalendar's own notifications (before each event, at its
  Google reminder times or 10 minutes before; Join, Open, Snooze, Dismiss),
  shown by the shell's notification server and silenced by Do Not Disturb.
  Other copies of the same reminder (the phone's calendar app mirrored by KDE
  Connect, Google Calendar in the browser) can be made quiet with
  `notifications.quiet` (Settings → Notifications → Quiet: apps and rules, in
  the cut-in rule syntax, whose notifications don't pop up, cut in or chime
  but still reach the notification centre and the history).

Each of these widgets has the same account button: "Connect a Google account"
until one is connected (the browser opens Google's login: dcal ships its own
OAuth client, so no Google Cloud project is needed), then "Open DankCalendar"
(events, tasks, the other accounts: Microsoft, CalDAV, iCloud, iCal feeds);
right click syncs now. The desktop menu's widget list scrolls when it is
taller than the screen. The assistant answers "how do I sync my Google
calendar?" and the like (`assistant.howTo.calendar*`).

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

## Themes

The theme is `appearance.theme` — Settings → Appearance → Theme, or the
desktop menu's Theme submenu — and each theme with variants keeps its own
`appearance.<theme>.variant`, so switching theme and back keeps the variant:

| Theme      | Variants                                         | Own settings (`appearance.<theme>.*`)              |
| ---------- | ------------------------------------------------ | -------------------------------------------------- |
| `material` | —                                                | —                                                  |
| `persona`  | `p5` (Royal), `p3r` (3 Reload), `p4` (4 Revival) | `palette`, `motion`, `shapes`, `halftone`, `fonts` |
| `chiikawa` | `chiikawa` (default), `usagi`, `momonga`         | `palette`, `motion`, `shapes`, `fonts`, `mascot`   |

```nix
programs.nixbook-shell.settings.appearance = {
  theme = "chiikawa";          # an enum of the themes: a typo fails evaluation
  chiikawa.variant = "usagi";  # likewise, the theme's variants
};
```

Each theme variant also keeps its own desktop, lock screen and login screen
wallpapers (`appearance.wallpaperPerTheme`, on by default;
`appearance.themeWallpapers`, `themeLockWallpapers`, `themeLoginWallpapers`:
`"<theme>/<variant>=<path>"` entries, `src/services/ThemeWallpapers.qml`):
switching puts back what the variant had (for the desktop, its bundled one
the first time: the Chiikawa ones; for the lock and login screens, nothing:
they follow the desktop, then the lock screen), and a wallpaper picked while
in a variant becomes that variant's. Settings → Appearance → Theme sets or
unsets all of them at once, in a table of every variant. Each theme has its own sounds too (`sounds` in `themes.json`: the
notification chime and the critical sound — Persona 5's by default, the
characters' own in Chiikawa); a file set in the settings wins. Important
notifications (critical ones, and those the cut-in rules pick:
Settings → Bar → Notifications → Cut-ins) get the theme's cut-in: the
full-screen Persona one, or the Chiikawa character popping up with a speech
bubble (`ChiikawaAlert.qml`).

Before `appearance.theme` the Persona style was the switch
`appearance.persona.enable`. It still works: a `config.json` holding it is
migrated to `theme = "persona"` when the shell loads it, and the Nix option is
translated to `appearance.theme` with a deprecation warning.

### Adding a theme

The themes are declared once, in `src/modules/common/themes.json`, which the
shell (`Themes.qml`), the Nix options (`lib.nix`), the login screen
(`scripts/theme-palettes.py`) and niri's first frames all read:

1. Add an entry to `themes.json`: `id` (lowercase letters and digits: it is a
   settings key), `name`, `icon` (a Material Symbol), `description`,
   `variants` (each `id`, `name`, `icon` and an optional `palette`: the roles
   `theme-palettes.py` lists, which replace the wallpaper palette),
   optionally `defaultVariant` and a `style` — the look as data, applied by
   `Appearance.qml`: `rounding` (scale of the corner radii), `fonts`
   (`main`, `title`, `numbers`) and `motion` (bezier curves `slam`, `snap`,
   `quick`, `exit`); a variant's own `style` overrides its theme's. Also
   optional, on the theme or a variant: `wallpaper` (a path in `src/`, shown
   the first time the variant is picked) and `sounds` (`notification`,
   `critical`: paths in `src/`, overriding the top-level defaults).
2. With variants, add `property JsonObject <id>` under `appearance` in
   `src/modules/common/Config.qml`, holding at least `variant` (and any of
   `palette`, `shapes`, `fonts`, `motion`: false turns that part of the
   style off), then regenerate `builtin-defaults.json`
   (`nixbook-shell config builtin`).
3. For anything data can't express, a singleton gated on `Themes.is("<id>")`
   (`Persona.qml`, `Chiikawa.qml`) and an options section in
   `src/modules/ii/settings/pages/AppearanceConfig.qml`. The theme list,
   variant list and desktop submenu need nothing: they come from the
   registry. A font the theme uses goes in `hm-module.nix`'s `home.packages`.

The Chiikawa art (the characters, the sidebar patterns and the wallpapers) is
drawn by `src/assets/chiikawa/generate.py` from the variants' palettes; rerun
it after changing them. Its sounds are synthesized when the package is built
(`src/assets/chiikawa/sounds.py`, no audio file in git).

Settings that did nothing were removed (`lib.nix` `removedKeys`: the parallax
options, `bar.topLeftIcon`, the settings window border…); an old Nix
configuration setting one still evaluates, with a warning, and the value is
ignored.

## Layout

| Path               | What                                                                               |
| ------------------ | ---------------------------------------------------------------------------------- |
| `default.nix`      | entry point (`package`, `homeManagerModules.default`, `lib`)                       |
| `package.nix`      | the launcher: runtime `PATH`, QML import path, `config` CLI                        |
| `dankcalendar.nix` | DankCalendar (`dcal`), the calendar and task sync, from `npins/`                   |
| `qml.nix`          | the QML tree as installed (store-path fixups, Persona and Chiikawa art)            |
| `quickshell.nix`   | Quickshell from `quickshellSrc` plus `patches/`                                    |
| `lib.nix`          | typed settings options generated from `builtin-defaults.json`                      |
| `hm-module.nix`    | the Home Manager module `programs.nixbook-shell`                                   |
| `nixos-module.nix` | optional NixOS module: the system's toggles for the assistant                      |
| `greeter.nix`      | the login screen (`nixbook-shell.greeter`, imported by it)                         |
| `toggles.nix`      | discovers the `enable` toggles from an options tree                                |
| `scripts/`         | `config` CLI, its jq library, assistant facts, Anthropic usage, login screen theme |
| `npins/`           | default nixpkgs, quickshell, dankcalendar (+ flake-compat) pins                    |
| `src/`             | the vendored QML tree (edited in place)                                            |
| `tests/`           | script tests, lib unit tests, the self-containment check                           |

## Tests

```sh
bash tests/scripts.sh
nix-instantiate --eval --strict --json --expr 'import ./tests/lib.nix { }'   # []
nix-instantiate --eval --strict --read-write-mode tests/standalone.nix \
  --arg homeManager '<home-manager checkout>'                                  # "ok"
```

`bash tests/perf.sh` (`tests/run.sh shell-perf` in nixbook) is the
performance score: the shell in a headless sway (software rendering, Nix's
pinned tools, a throwaway home), once per theme (Material, Persona 5 Royal,
Chiikawa), measuring startup (until the QML is loaded), idle CPU over 30 s
after 20 s to settle, and resident memory; `score = 1000 / mean(startup_s +
cpu_% + rss_MB / 100)`, higher is better. Compare scores from the same
machine only; nixbook's AGENTS.md keeps the latest.
