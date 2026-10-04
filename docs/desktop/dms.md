# DankMaterialShell

[DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) (DMS) is a Quickshell-based, compositor-agnostic desktop shell (Niri, Sway, Hyprland) with a top bar, an optional dock, a control centre, notifications, a launcher and a lock screen. `customHomeManagerModules.dmsConfig` configures it.

```nix
customHomeManagerModules.dmsConfig = {
  enable = true;
  showDock = true;           # dock below the bar
  enableNixosUpdate = true;  # update widget (default)
  enableDankCalendar = true; # DankCalendar app and daemon
};
```

::: warning
DMS and [nixbook-shell](/nixbook-shell/) are mutually exclusive.
:::

## Features

- System monitoring widgets (dgop), **wallpaper-based Material theming** (matugen), an audio visualiser (cava), calendar events;
- a systemd user service that restarts on configuration changes;
- low (20 %) and critical (10 %) battery notifications.

## Bar layout

| Left                                               | Centre                                                      | Right                                                                                |
| -------------------------------------------------- | ----------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| Launcher, NixOS update, workspaces, focused window | Music, clock, weather, OpenCode usage, GitHub notifications | Tray, markets, VPN status, CPU, notifications, KDE Connect, control centre, Sathi AI |

## Plugins

| Plugin                               | Source                         | What                                                                                                 |
| ------------------------------------ | ------------------------------ | ---------------------------------------------------------------------------------------------------- |
| `nixosUpdate`                        | nixbook (`assets/dms/plugins`) | Shows when an update is available and runs it ([osupdate](/installation/deploy-and-update#osupdate)) |
| `vpnStatus`                          | nixbook                        | Tailscale / NetBird status                                                                           |
| `githubNotifierCustom`               | nixbook                        | GitHub notifications                                                                                 |
| `opencodeUsage`                      | nixbook                        | OpenCode token usage (with `opencodeConfig`)                                                         |
| `markets`                            | DMS registry                   | Market ticker                                                                                        |
| `dankGifSearch`, `dankStickerSearch` | DMS registry                   | GIF and sticker search                                                                               |
| `dankKDEConnect`                     | DMS registry                   | KDE Connect                                                                                          |
| `sathiAi`                            | DMS registry                   | AI assistant widget (**Mod+Space**)                                                                  |

## DankCalendar

With `enableDankCalendar`, [DankCalendar](https://github.com/AvengeMedia/dankcalendar) (`dcal`) is installed with its background daemon (sync and reminders): local, Google, Microsoft, CalDAV and iCloud calendars.

## Theming

DMS themes itself with matugen, so Stylix's DMS target is off and Stylix pins the tomorrow-night base16 scheme for the rest of the system (see [Theming](/user/theming#stylix)).
