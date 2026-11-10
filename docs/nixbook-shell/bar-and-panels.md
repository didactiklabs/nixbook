# Bar, launcher & panels

## The bar

The bar's layout (left, centre, right) is edited in **Settings → Bar** (or pinned in Nix); it can sit at the top or bottom, or be vertical, and be shown on chosen monitors. **Mod+B** toggles it.

### Widgets

| Widget              | What it does                                                                                              |
| ------------------- | --------------------------------------------------------------------------------------------------------- |
| Launcher button     | Opens the launcher                                                                                        |
| Left sidebar button | Opens the AI chat / translator sidebar                                                                    |
| Workspaces          | Niri workspaces of the monitor                                                                            |
| Active window       | Title and app of the focused window                                                                       |
| Clock               | Time and date; popup with the week's events and pending tasks; click opens the Calendar                   |
| Next event          | "in 12 min" and the title; joins the meeting when it is about to start ([Calendar](./calendar))           |
| Media               | Now playing; scroll switches player ([Media](./media))                                                    |
| Visualizer          | Audio spectrum                                                                                            |
| Weather             | Current weather                                                                                           |
| Resources           | CPU, memory, temperatures                                                                                 |
| Network speed       | Up/down throughput                                                                                        |
| System icons        | Volume, microphone, network, Bluetooth, unread notifications — each with a hover card                     |
| Battery             | Charge and state                                                                                          |
| Bluetooth           | Connected devices                                                                                         |
| Keyboard layout     | The active layout / input method                                                                          |
| Tray                | System tray                                                                                               |
| Util buttons        | Screenshot, colour picker and screen recording (with its timer)                                           |
| [Updates](#updates) | Whether the machine is behind the repository; runs the update                                             |
| [VPN](#vpn)         | Tailscale and NetBird status and control                                                                  |
| Phone Connect       | KDE Connect devices ([Media & phone](./media#phone-connect))                                              |
| Claude usage        | Remaining Claude quota in the 5-hour and weekly windows                                                   |
| Desktop control     | AI agents' activity and the pause button ([Desktop control](./desktop-agents#the-desktop-control-widget)) |
| Dock to panel       | The dock's apps inside the bar                                                                            |
| Dynamic island      | A compact pill that expands for media, notifications, volume/brightness, timers and the session           |
| Power button        | Session menu                                                                                              |
| Divider             | Spacing                                                                                                   |

The bar tells you what the pointer can do while you hover a widget: an **accent notch** on the side means hovering opens a popup, a **hand cursor and soft highlight** means clicking does something.

### Updates

The _Updates_ widget compares `/etc/nixos/version` with the repository (`updates.repoUrl`; nixbook sets its own). Hover for the deployed revision and branch, whether it was deployed from a dirty tree, the latest revision and the last run's result. Click for a panel with **Check**, **Execute** (runs the update service, passwordless through polkit), the changelog and a live, copyable journal of the run; right-click re-checks. The same controls are in **Settings → Services**.

### VPN

Hover shows Tailscale and NetBird status, IPs and exit node. The panel toggles each VPN, switches tailnet or NetBird profile and sets or clears the exit node, updating optimistically and reverting on failure.

## Launcher

**Mod+D** opens the launcher. It searches apps with a tiered, typo-tolerant scorer (name, executable, keywords, description…) ranked by how often you use them, and switches mode with a prefix:

| Prefix | Mode                                | Shortcut |
| ------ | ----------------------------------- | -------- |
| _none_ | Apps (and default actions)          | Mod+D    |
| `>`    | Apps only                           |          |
| `;`    | Clipboard history                   | Mod+Q    |
| `:`    | Emoji                               |          |
| `.`    | Symbols                             |          |
| `=`    | Calculator                          |          |
| `$`    | Run a shell command                 |          |
| `?`    | Web search                          |          |
| `/`    | Shell actions                       |          |
| `@`    | Themes and variants                 | Mod+X    |
| `#`    | [Window layouts](./window-layouts)  | Mod+G    |
| `~`    | [Find it](./desktop-agents#find-it) |          |

The launcher also adds tasks to the to-do list.

## Sidebars

Besides their shortcuts and bar buttons, both open from the middle of their screen edge: click the pill to open one to stay, or hold the pointer against the edge a moment (`sidebar.edgeHandles.hoverDelay`, 200 ms by default, or turn `hoverToOpen` off; Settings → Panels) for a peek. A peek is only a glance until you use it, by moving into it and staying a moment or by clicking it: until then your keyboard stays with the window you were in, and moving off the panel closes it at once. A used peek takes the keyboard, and closes shortly after the pointer leaves it.

### Right sidebar — Mod+N

Quick settings on top, and one page at a time below them, so each gets the whole height:

- **the header** — who you are and the uptime, over your wallpaper, with the buttons to edit the toggles, reload, pin the panel, open Settings and open the session menu. Click the picture to choose another, right-click to go back to the wallpaper (`sidebar.banner` off: no picture);
- **quick toggles** — network, Bluetooth, sound and microphone mute, dark mode, night light, idle inhibitor, Do Not Disturb, power profile, EasyEffects, on-screen keyboard, screenshot, colour picker — in a classic or Android-style panel, with details pages for **Wi-Fi networks**, **Bluetooth devices** and the **volume mixer**;
- **sliders** for brightness, volume and microphone, each with its value;
- **the pages**, picked in the tab strip or with Ctrl+Page Up/Down: the **notification centre** with its [history](./notifications#history), a **calendar** with the day's events under the month (click a day to list its events, click it again to go back to today), the **to-do list** and a **pomodoro timer**.

**Jellyfin** (once Jellyfin is signed in on this computer; Settings → Panels → Right Sidebar → Jellyfin tab turns it off): _Up next_ — what you started, then the next episode of each series you follow — as wide thumbnails with how far you got, and _Recently added_ as posters, three a row. A click plays it in mpv on this computer (jellyfin-mpv-shim), where you stopped; the refresh button (or every 10 minutes while it shows) updates the list.

The panel remembers the page you left it on, but opens on Notifications when something arrived while it was closed; from another page, a badge on the bell counts them. Settings → Panels → Right Sidebar turns off the pages other than Notifications.

It can be **pinned** too: the pin in its header, or Ctrl+P inside it (`nixbook-shell ipc call sidebarRight pin|unpin|togglePin`). Pinned, it stays open beside your windows, which make room for it, on the monitor it was pinned on, even across reboots; closing it is refused until you unpin it. Notification popups still show while it is pinned, unless its Notifications page is the one in view.

### Left sidebar — Mod+Space

- the [AI chat](./ai-assistant);
- a **translator**.

It can be **pinned** (Ctrl+P) to stay open beside your windows — on the monitor it was pinned on, even across reboots — or extended (Ctrl+O).

## Dock

A dock with pinned and running apps (pins can be set from Nix), magnifying and bouncing icons, and a media card with full playback controls.

## Other panels

| Panel              | Opens with                   | What                                                                              |
| ------------------ | ---------------------------- | --------------------------------------------------------------------------------- |
| Overview           | Mod+O                        | Workspaces overview                                                               |
| Session menu       | Mod+L                        | Lock, log out, suspend, reboot, power off — warns when an update or GC is running |
| Wallpaper selector | Mod+W                        | [Wallpapers](./desktop-and-wallpapers#wallpapers)                                 |
| OSD                | volume / brightness keys     | On-screen indicator                                                               |
| Media controls     | bar / IPC                    | [Players](./media)                                                                |
| Equalizer          | media controls               | [EasyEffects equalizer](./media#equalizer)                                        |
| Desktop menu       | right-click on the desktop   | Wallpaper, widgets, theme, window layouts                                         |
| Overlay            | IPC                          | Pinned floating widgets                                                           |
| Screen translator  | IPC                          | Translate text on screen                                                          |
| On-screen keyboard | IPC (`osk`)                  | Virtual keyboard                                                                  |
| Polkit prompt      | when an app needs privileges | Themed authentication dialog (takes the keyboard at once)                         |

Panels take the keyboard focus as soon as they open, close when you click outside or switch workspace, and only one dismissable popup is open at a time.
