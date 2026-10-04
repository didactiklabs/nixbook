# Niri

[Niri](https://github.com/YaLTeR/niri) is a scrollable-tiling Wayland compositor: windows are arranged in **columns on an infinite horizontal strip**, and workspaces stack vertically per monitor. It is Nixbook's preferred compositor.

## Enable it

```nix
# NixOS (profile)
customNixOSModules.niri.enable = true;

# Home Manager (user)
customHomeManagerModules.niriConfig.enable = true;
```

## System module

`customNixOSModules.niri`:

- the niri-flake NixOS module (pinned with npins) running nixpkgs' Niri, with the niri.cachix.org binary cache;
- **polkit-gnome** as authentication agent — set `polkitAgent = false` when the shell provides its own (nixbook-shell does);
- Wayland utilities: fuzzel, grimblast, wl-clipboard, libnotify, **xwayland-satellite** for X11 apps;
- `nm-applet` / `nm-connection-editor` (WPA Enterprise prompts), the GTK file chooser portal, the GNOME portal backend and the Secret portal → GNOME Keyring;
- a hyprlock PAM service with U2F and keyring re-unlock;
- `accessibility` (on by default): the at-spi accessibility bus;
- on NVIDIA, the driver profile that keeps Niri's VRAM usage in check.

## User configuration

`homeManagerModules/niri/niriConfig.nix` manages the whole Niri configuration declaratively:

- **key bindings** — see [Keybindings](./keybindings#niri-scrollable-tiling-compositor-totoro-tanjiro-nishinoya-hanamichi);
- **window rules**: windows at 85 % opacity with per-app exceptions, rounded corners, and **xray blur** for every window (the wallpaper blurred once and cached — cheap on integrated GPUs); a few popups (e.g. a video call) stay opaque;
- 10 px gaps, a focus ring, client-side decorations disabled, hot corners off;
- idle management with [hypridle](./#idle-and-locking-niri);
- the desktop shell's panels bound to keys through `nixbook-shell ipc call …` / `dms ipc call …`;
- `swaybg` for the wallpaper only when nixbook-shell (which paints its own) is off;
- **theme-coloured window animations** with nixbook-shell: the shell rewrites an included `nixbook-shell-animations.kdl` with its palette, so open/close animations (e.g. the Persona slash) follow the theme live.

Per-user and per-machine overrides (monitor layout, scales, extra binds) live in the profile, e.g. `profiles/totoro/khoa/niriConfig.nix`.

## Concepts

| Term      | Meaning                                                         |
| --------- | --------------------------------------------------------------- |
| Column    | A vertical stack of windows; the strip scrolls column by column |
| Workspace | A strip; workspaces are stacked vertically on each monitor      |
| Output    | A physical monitor, each with its own workspaces                |
| Overview  | A zoomed-out view of every workspace (**Mod+Tab**)              |
