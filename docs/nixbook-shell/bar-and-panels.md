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
| Clock               | Time and date; popup with the week's events and pending tasks; click opens DankCalendar                   |
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
| Music recognition   | Identify the song playing (songrec)                                                                       |
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

| Prefix | Mode                               | Shortcut |
| ------ | ---------------------------------- | -------- |
| _none_ | Apps (and default actions)         | Mod+D    |
| `>`    | Apps only                          |          |
| `;`    | Clipboard history                  | Mod+Q    |
| `:`    | Emoji                              |          |
| `.`    | Symbols                            |          |
| `=`    | Calculator                         |          |
| `$`    | Run a shell command                |          |
| `?`    | Web search                         |          |
| `/`    | Shell actions                      |          |
| `@`    | Themes and variants                | Mod+X    |
| `#`    | [Window layouts](./window-layouts) | Mod+G    |

The launcher also adds tasks to the to-do list.

## Sidebars

### Right sidebar — Mod+N

Quick settings and notifications:

- **quick toggles** — network, Bluetooth, sound and microphone mute, dark mode, night light, idle inhibitor, Do Not Disturb, power profile, EasyEffects, on-screen keyboard, screenshot, colour picker, music recognition — in a classic or Android-style panel, with details pages for **Wi-Fi networks**, **Bluetooth devices** and the **volume mixer**;
- **sliders** for brightness, volume and microphone;
- the **notification centre** with its [history](./notifications#history);
- a calendar with events, the to-do list and a pomodoro timer.

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
| Desktop menu       | right-click on the desktop   | Wallpaper, widgets, theme, window layouts, agents' desktop                        |
| Overlay            | IPC                          | Pinned floating widgets                                                           |
| Screen translator  | IPC                          | Translate text on screen                                                          |
| On-screen keyboard | IPC (`osk`)                  | Virtual keyboard                                                                  |
| Polkit prompt      | when an app needs privileges | Themed authentication dialog (takes the keyboard at once)                         |

Panels take the keyboard focus as soon as they open, close when you click outside or switch workspace, and only one dismissable popup is open at a time.
