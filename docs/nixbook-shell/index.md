# nixbook-shell

**nixbook-shell** is nixbook's own desktop shell for [Niri](/desktop/niri), written in QML with [Quickshell](https://quickshell.outfoxxed.me): bar, dock, sidebars, launcher, notifications, lock and login screens, desktop widgets, an AI chat, and a choice of themes.

It started as a fork of [pctrade/end4-pC](https://github.com/pctrade/end4-pC), itself a fork of end-4's _illogical-impulse_; it is now its own project, Niri-only, with no upstream to track (credits and licence in `nixbook-shell/src/`).

## Highlights

|                                                          |                                                                                                                         |
| -------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| [Settings](./settings)                                   | Every option editable in a Settings window — and lockable from Nix, key by key                                          |
| [Themes](./themes)                                       | Material (from the wallpaper), Persona, Chiikawa, Cyberpunk 2077, Studio Ghibli — with their own art, sounds and motion |
| [Bar, launcher & panels](./bar-and-panels)               | ~25 bar widgets, a fuzzy launcher with prefixes, two sidebars, dock, OSD, overview                                      |
| [Notifications](./notifications)                         | Inline replies, cut-ins for important messages, de-duplication, quiet rules, a searchable history                       |
| [Calendar & tasks](./calendar)                           | Google/Microsoft/CalDAV calendars and tasks through DankCalendar, in the bar, sidebar and desktop                       |
| [Desktop widgets & wallpapers](./desktop-and-wallpapers) | Clock, weather, notes, to-do, timers, visualiser… per monitor; live video wallpapers                                    |
| [Media & phone](./media)                                 | Player selection, per-player volume, equalizer, music recognition, KDE Connect                                          |
| [Screenshots & recording](./screenshots)                 | Rectangle, circle, window or screen selection; annotation; recording with audio                                         |
| [Window layouts](./window-layouts)                       | Save where every window is and restore it in one key                                                                    |
| [Lock & login screens](./lock-and-login)                 | Themed lock screen and greeter, security-key cues, a seamless loading screen                                            |
| [AI chat & config assistant](./ai-assistant)             | An offline assistant that answers from your configuration, and Claude in the side panel                                 |
| [Desktop control for AI agents](./desktop-agents)        | An MCP server that lets agents see and drive the desktop, with guardrails and memory                                    |
| [The agents' own desktop](./agent-desktop)               | A sandboxed nested desktop where agents work without touching yours                                                     |

None of the themes blur a shadow, keeping the shell light on integrated GPUs; the shell has been profiled for latency, idle CPU and GPU cost (popups stay mapped and open in ~40 ms, animations stop when nothing is visible, background work pauses when the screens are off).

## Enable it in nixbook

```nix
# Home Manager (profiles/<host>/<user>/default.nix)
customHomeManagerModules = {
  niriConfig.enable = true;
  nixbookShellConfig.enable = true;
  dmsConfig.enable = false;   # the two shells are mutually exclusive
};

# NixOS (profiles/<host>/default.nix)
customNixOSModules = {
  niri = {
    enable = true;
    polkitAgent = false;      # the shell has its own polkit prompt
  };
  greetd.enable = true;       # its login screen becomes the default greeter
};
```

`nixbookShellConfig` wraps the shell's own Home Manager module: it applies the settings shared by every nixbook machine (`homeManagerModules/nixbookShellConfig/settings.nix`, as defaults a profile can override key by key), passes nixbook's Quickshell pin, binds the panels to Niri keys, and gives the assistant this machine's context (host, enabled modules, profile paths, how to deploy).

## How it runs

- The shell is the `nixbook-shell` **user service**, bound to the graphical session.
- `nixbook-shell` is the launcher; `nixbook-shell ipc call <target> <function>` drives it from key bindings and scripts:

```bash
nixbook-shell ipc call search toggle          # launcher
nixbook-shell ipc call sidebarLeft toggle     # AI chat / translator
nixbook-shell ipc call sidebarRight toggle    # notifications & quick settings
nixbook-shell ipc call settings toggle        # Settings window
nixbook-shell ipc call search themeToggle     # theme switcher
nixbook-shell ipc call lock activate          # lock the screen
```

The IPC targets include `bar`, `background`, `brightness`, `calendar`, `desktopControl`, `equalizer`, `images`, `layouts`, `lock`, `mediaControls`, `mpris`, `musicRecognition`, `notes`, `notificationHistory`, `osk`, `overlay`, `region`, `screenTranslator`, `search`, `session`, `settings`, `sidebarLeft`, `sidebarRight`, `theme`, `timers`, `todo`, `wallpaper`, `wallpaperSelector`, `widgets`.

See the [keybindings](/desktop/keybindings#applications-shell) for what is bound by default.

## Using it outside nixbook

The `nixbook-shell/` directory is **self-contained** — nothing in it refers to the rest of the repository, and CI checks that by evaluating a copy of it alone. Use it in any Home Manager configuration:

```nix
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

`import ./nixbook-shell { }` returns:

| Attribute                    | What                                                                        |
| ---------------------------- | --------------------------------------------------------------------------- |
| `package`                    | The `nixbook-shell` launcher                                                |
| `homeManagerModules.default` | The Home Manager module above (`programs.nixbook-shell`)                    |
| `nixosModules.default`       | Optional NixOS module: the login screen, and system facts for the assistant |
| `lib`                        | The settings helpers                                                        |

Arguments: `pkgs`, `quickshellSrc` (another Quickshell pin), `withTailscale` / `withNetbird` (leave a VPN CLI out of the shell's PATH — done automatically on NixOS when the service is off).

### Home Manager options

| Option                                        | Default | What                                                                      |
| --------------------------------------------- | ------- | ------------------------------------------------------------------------- |
| `programs.nixbook-shell.enable`               | `false` | Install and run the shell                                                 |
| `programs.nixbook-shell.settings`             | `{}`    | Typed shell settings, [locked in the Settings window](./settings)         |
| `programs.nixbook-shell.cliphist.enable`      | `true`  | Run the cliphist daemon behind the clipboard history                      |
| `programs.nixbook-shell.splash.enable`        | `true`  | The [loading screen](./lock-and-login#loading-screen) from session start  |
| `programs.nixbook-shell.appTheming.qt.enable` | `false` | Qt apps follow the shell's palette ([App colours](./themes#app-colours))  |
| `programs.nixbook-shell.desktopMcp.*`         |         | The [desktop control server](./desktop-agents#configuration)              |
| `programs.nixbook-shell.assistant.*`          |         | What the [assistant](./ai-assistant#teaching-it-about-your-machine) knows |

## Source layout

| Path                              | What                                                                                       |
| --------------------------------- | ------------------------------------------------------------------------------------------ |
| `default.nix`                     | Entry point                                                                                |
| `package.nix`                     | The launcher: runtime `PATH`, QML import path, `config` CLI                                |
| `qml.nix`                         | The installed QML tree, with theme art and sounds built at build time                      |
| `quickshell.nix`                  | Quickshell from its pin plus `patches/`                                                    |
| `dankcalendar.nix`                | DankCalendar (`dcal`), the calendar and task sync                                          |
| `fonts.nix`                       | Fonts nixpkgs lacks (Google Sans Flex, Space Grotesk, Rajdhani, Zen Maru Gothic, Klee One) |
| `lib.nix`                         | Typed settings options generated from `builtin-defaults.json`                              |
| `hm-module.nix`                   | `programs.nixbook-shell`                                                                   |
| `nixos-module.nix`, `greeter.nix` | NixOS side: system facts, the login screen                                                 |
| `scripts/`                        | `config` CLI, assistant facts, desktop control MCP server, agent desktop, greeter theme…   |
| `src/`                            | The QML tree                                                                               |
| `tests/`                          | Script tests, lib unit tests, the self-containment check                                   |
