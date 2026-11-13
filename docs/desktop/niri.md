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
- 10 px gaps, a focus ring, a soft drop shadow outside each window, client-side decorations disabled, hot corners off;
- the **Alt+Tab** window switcher (niri's recent windows) in the theme's colours;
- volume, microphone, brightness and **media keys** (play/pause, next, previous; nixbook-shell's chosen player, else playerctl) that also work on the lock screen;
- niri's own list of shortcuts on **Mod+F1**, every shell bind with a readable title;
- [screen sharing](#screen-sharing) helpers;
- idle management with [hypridle](./#idle-and-locking-niri);
- the desktop shell's panels bound to keys through `nixbook-shell ipc call …` / `dms ipc call …`;
- `swaybg` for the wallpaper only when nixbook-shell (which paints its own) is off;
- **theme-coloured window animations** with nixbook-shell: the shell rewrites an included `nixbook-shell-animations.kdl` with its palette, so open/close animations (e.g. the Persona slash) follow the theme live.

## Screen sharing

Screen sharing goes through `xdg-desktop-portal-gnome`, which niri drives: its dialog offers whole screens and single windows. Some apps (Zoom, some Electron apps) only ask for screens, and then the dialog has no Window tab.

- **Dynamic cast target**: pick the window "niri Dynamic Cast Target" in the dialog once. It starts empty; **Mod+Alt+W** then shows the focused window, **Mod+Alt+M** the focused monitor and **Mod+Alt+C** nothing, without sharing again.
- The window being shared (a window share or the dynamic target) gets a **red frame**.
- **Blocked out** for viewers (a black box; your screen and screenshots are unchanged): password managers, authenticators and password prompts (pinentry, the keyring's), private browsing windows, and the shell's notification popups, cut-ins, DAI's bubble and smart clipboard chips (DMS's notification popups too).
- **Mod+Ctrl+Shift+F**: windowed fullscreen. The app thinks it is fullscreen but stays a normal window, to share a slideshow without the browser's toolbars.

Blocking out covers the screencast portal only. The shell's screenshot selector shows a frozen copy of the screen, so while you take a screenshot during a share, viewers may briefly see a blocked window.

## Windows that open where they were

Niri opens every new window at the default width, next to whatever has focus, on the workspace you're looking at. Some apps replace their window with a new one: **Moonlight** hides its window while a game streams and opens a stream window, then does the reverse when the game ends; **Discord** (Vesktop) shows a splash, then opens its main window, each time it starts or restarts itself. Their window used to lose its size and place each time.

The `niri-keep-place` user service handles the apps in `customHomeManagerModules.niriConfig.keepPlace.apps` (default: Moonlight and Vesktop). A new window of one of them goes to the place of the app's other open window, else of its last one, remembered across launches and reboots: the same workspace, floating or tiled like it, the same size, and the same column or floating position.

- The column is only restored while the new window has the focus (niri can only move the focused column).
- After a reboot, workspaces have new ids: the window goes to the workspace with the same name, else the same index on the same monitor. If none exists, it stays where it opened (still at its size).
- `titles` limits an app to its main window: Vesktop's is titled `Discord…`, so its splash and popouts open as usual.
- The places are kept in `~/.local/state/niri-keep-place/places.json`.

```nix
customHomeManagerModules.niriConfig.keepPlace.apps = {
  "com.moonlight_stream.Moonlight" = { };
  vesktop.titles = [ "Discord( \\||$)" ];
  "some.other.App" = { }; # niri msg windows shows each window's app id
};
```

Set it to `{ }` to turn the service off.

Per-user and per-machine overrides (monitor layout, scales, extra binds) live in the profile, e.g. `profiles/totoro/khoa/niriConfig.nix`.

## Concepts

| Term      | Meaning                                                         |
| --------- | --------------------------------------------------------------- |
| Column    | A vertical stack of windows; the strip scrolls column by column |
| Workspace | A strip; workspaces are stacked vertically on each monitor      |
| Output    | A physical monitor, each with its own workspaces                |
| Overview  | A zoomed-out view of every workspace (**Mod+Tab**)              |
