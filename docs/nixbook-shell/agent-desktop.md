# The agents' own desktop

So an agent can work **while you work**, it can be given a desktop of its own: a nested, sandboxed Niri shown on your desktop as a window called **"Assistant's desktop"**. Every agent tool then acts there — its own pointer, keyboard focus, clipboard and windows — so nothing the agent does moves your windows, takes your focus or types into what you are typing.

## Switching

| To…                                             | Use                                                                                                                                                |
| ----------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| Give agents their own desktop / bring them back | **Mod+Shift+A**, right-click the Desktop Control widget, the desktop menu, Settings → Desktop agents, `nixbook-desktop-mcp desktop agent` / `user` |
| Take it over for a moment                       | **Mod+Ctrl+A**, the desktop menu's _Use it myself_, `nixbook-desktop-mcp desktop interact on/off`                                                  |
| Close it                                        | Close its window, or `nixbook-desktop-mcp desktop stop`                                                                                            |
| Check                                           | `nixbook-desktop-mcp desktop status`                                                                                                               |

The choice survives reboots, and an agent already at work is told when you switch.

## How it behaves

- It is **never open empty**: it opens beside your work (without taking the focus, with a notification) when an agent starts an app, and closes once the agent's last app is gone.
- It shows **one app at a time, fullscreen**, with no bar, borders or focus ring; the agent's other apps stay open behind it and come back with `focus_window`.
- The window is **a view, not a way in**: its Niri drops your clicks and keys, so you watch the agent work, and move or resize the window like any other. To use it yourself (e.g. to log the agent's browser into a site), **take it over** — the agent's window and input tools are refused until you give it back.
- Closing the window only closes it: the agent's next app opens it again. To stop agents, switch them back to your desktop or pause them (Mod+Shift+Escape).
- The bar widget shows a window icon beside the robot while agents are on their own desktop.

## Sandbox

Its apps are the agent's, not yours, and run in a **bubblewrap sandbox**:

- **They see none of your files.** Their home is `~/.local/share/nixbook-shell/agent-home` (their own browser profiles, history and logins); your GTK/Qt/font settings are visible read-only so apps look the same.
- Their own D-Bus session (no keyring, portals or notifications of yours), no system bus, none of your runtime sockets (session bus, audio, X11, the MCP token), and their own process namespace.
- **Your desktop only through a restricted connection**: its Niri reaches yours through a Wayland _security-context_ socket (the way Flatpak does it), so nothing in the sandbox can capture your screen, type into it, read your clipboard or list your windows — it can only show its window.

Two switches in **Settings → Desktop agents** (both on):

- **Hide the system's services from their apps** — `/run` is empty but for what apps need, so no system daemon's socket is reachable.
- **Keep their apps off this computer's local services** — their own network namespace (pasta): the internet and your LAN, but not what listens on `127.0.0.1` (a dev server, the printer and Sunshine pages). If the network can't be set up, the desktop doesn't open.

### Shared folders

- **Folders AI agents may read** (`ai.allowedFolders`) are visible read-only, at the same path as in your home.
- **Folders the agents' desktop may write** (`ai.writableFolders`) are bound read-write, and the first one is its apps' Downloads folder — so an agent can download a file in its browser and use it on your side, a wallpaper for instance.

## What still reaches your desktop

The shell tools — notes, to-do list, timers, calendar, notifications, themes — act on **your** shell whichever desktop the agent is on. So an agent can look for flats in its own browser and write what it found into your notes widget. Only the generic shell IPC is refused from the agent desktop, since the panels it opens would appear on your screen.

::: tip Why not a second seat in your Niri?
Niri has one focus and one view per workspace, and most apps ignore input from a second Wayland seat (Chromium, Electron and kitty entirely). A nested compositor works with every app and needs no change to your session.
:::
