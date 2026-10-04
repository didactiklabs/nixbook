# Desktop overview

Nixbook's desktop is **Wayland-only** and built from three independent layers, each chosen per machine or per user:

| Layer         | Options                                                                        | Configured by                                                                         |
| ------------- | ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------- |
| Login         | [greetd](./login) with tuigreet or nixbook-shell's login screen, or auto-login | `customNixOSModules.greetd`                                                           |
| Compositor    | [Niri](./niri) (scrollable tiling, preferred) or [SwayFX](./sway) (i3-like)    | `customNixOSModules.{niri,sway}` + `customHomeManagerModules.{niriConfig,swayConfig}` |
| Desktop shell | [nixbook-shell](/nixbook-shell/) or [DankMaterialShell](./dms)                 | `customHomeManagerModules.{nixbookShellConfig,dmsConfig}`                             |

The two desktop shells are **mutually exclusive** (both draw a top bar, own the lock screen and register overlapping layer-shell surfaces) — an assertion stops you from enabling both. Without a shell, Niri falls back to swaybg for the wallpaper, fuzzel as launcher and hyprlock as lock screen.

## Which to pick

|                | nixbook-shell                                              | DankMaterialShell                       |
| -------------- | ---------------------------------------------------------- | --------------------------------------- |
| Compositors    | Niri                                                       | Niri, Sway, Hyprland                    |
| Origin         | nixbook's own Quickshell shell                             | Upstream project, configured by nixbook |
| Themes         | Material (wallpaper), Persona, Chiikawa, Cyberpunk, Ghibli | Material (matugen)                      |
| Settings       | Nix-pinned **and** an in-shell Settings window             | Nix                                     |
| Login screen   | Its own greeter                                            | tuigreet                                |
| AI integration | Config assistant, Claude chat, desktop-control MCP         | Sathi AI widget                         |
| Used on        | totoro, tanjiro, hanamichi                                 | nishinoya                               |

## Idle and locking (Niri)

With Niri, `hypridle` manages idle time:

| After  | Action                                          |
| ------ | ----------------------------------------------- |
| 30 s   | Dim the screen, turn the keyboard backlight off |
| 1 min  | Lock the session                                |
| 5 min  | Turn the monitors off                           |
| 10 min | Suspend                                         |

**Mod+I** toggles idle inhibition. The lock screen is the desktop shell's (or hyprlock without a shell), with U2F and keyring re-unlock.

## Common pieces

- **Clipboard history** (cliphist), **screenshots** (grimblast, or the shell's region selector), **screen recording** (wf-recorder).
- **Polkit agent**: polkit-gnome, or nixbook-shell's built-in prompt (`customNixOSModules.niri.polkitAgent = false`).
- **Secret Service**: GNOME Keyring through the XDG Secret portal, unlocked at login and re-unlocked by the lock screens.
- **XWayland** apps through xwayland-satellite (Niri) or Sway's built-in XWayland.
- **Accessibility bus** (at-spi) on by default with Niri (`customNixOSModules.niri.accessibility`) — used by screen readers and nixbook-shell's AI agents.
