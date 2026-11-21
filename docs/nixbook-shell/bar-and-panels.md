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
| Network speed       | Up/down throughput, read every 3 s together with the resources                                            |
| System icons        | Volume, microphone, network, Bluetooth, unread notifications — each with a hover card                     |
| [Battery](#battery) | Charge and state; its panel sets the power profile and the charge limit                                   |
| Bluetooth           | Connected devices                                                                                         |
| Keyboard layout     | The active layout / input method                                                                          |
| Tray                | System tray                                                                                               |
| Util buttons        | Screenshot, colour picker and screen recording (with its timer)                                           |
| [Updates](#updates) | Whether the machine is behind the repository; runs the update                                             |
| [VPN](#vpn)         | Tailscale and NetBird status and control                                                                  |
| Phone Connect       | KDE Connect devices ([Media & phone](./media#phone-connect))                                              |
| Claude usage        | Remaining Claude quota in the 5-hour and weekly windows, and any one-model weekly limit (Fable)           |
| Desktop control     | AI agents' activity and the pause button ([Desktop control](./desktop-agents#the-desktop-control-widget)) |
| Dock to panel       | The dock's apps inside the bar                                                                            |
| Dynamic island      | A compact pill that expands for media, notifications, volume/brightness, timers and the session           |
| Power button        | Session menu                                                                                              |
| Divider             | Spacing                                                                                                   |

The bar tells you what the pointer can do while you hover a widget: an **accent notch** on the side means hovering opens a popup, a **hand cursor and soft highlight** means clicking does something.

### Updates

The _Updates_ widget compares `/etc/nixos/version` with the repository (`updates.repoUrl`; nixbook sets its own). Hover for the deployed revision and branch, whether it was deployed from a dirty tree, the latest revision and the last run's result. Click for a panel with **Check**, **Execute** (runs the update service, passwordless through polkit), **Next restart** (installs it as the system the next boot starts: nothing running changes until then; the widget then says it is installed and waiting for a restart, and **Apply now** switches to it at once), the changelog and a live, copyable journal of the run; right-click re-checks. The same controls are in **Settings → Services**.

**Automatic updates** (Settings → Services → System updates → _Install updates automatically_; off by default, or `updates.auto.enable` in the shell's Nix settings): once a check finds a newer revision, the update starts on its own in the background. It waits until:

- main's build of that revision is done for this machine and pushed to the cache (the check reads the `build (<host>)` and `push-cache` jobs from GitHub), so it downloads instead of compiling and a revision whose build failed is never installed; for a repository whose build can't be asked, an hour after the revision appeared;
- the laptop is on the charger (_Also on battery_: over 50 %);
- no window is fullscreen (a game, a film) and no meeting is under way;
- the system was deployed from `main` without local changes.

With _Only from the next restart_ (`updates.auto.nextBoot`), automatic updates are installed that way: nothing restarts in your session, and the update takes effect when you next reboot. A notification says when it starts and when it ends. One that fails isn't retried on its own: **Execute** retries it, and the next revision is tried as usual. The widget's hover card and panel say what an update is waiting for. With automatic updates on, the checks run even when _Enable update checks_ is off, and every 10 minutes while main is still building the revision.

An update that brings a new shell restarts it in the background: the bar and wallpaper blink back after a second or two, with no loading screen (see [Loading screen](./lock-and-login#loading-screen)).

### Battery

Hover or click the _Battery_ widget for its panel: charge, time left, health and power draw, and two things to choose (the panel stays open while the pointer is on it):

- **Power profile** — Power saver, Balanced or Performance, the profiles of power-profiles-daemon (also on the power profile quick toggle).
- **Charge limit** — 60 %, 80 % or 100 %: the level at which the battery stops charging. A lithium battery kept at 100 % on the charger ages much faster than one kept at 80 %, so keep 80 % day to day and pick 100 % before a trip. The choice survives reboots. While the charger is plugged in and the limit is reached, the panel says "Plugged in · held at 80%".

The charge limit shows on laptops whose firmware has one (the kernel's `charge_control_end_threshold`: ASUS, Framework, ThinkPad…). Setting it goes through a system unit of [`laptopProfile`](/system/hardware#laptops), without a password for the person at the computer; where that unit is missing and the file isn't writable, the panel shows the limit without letting you change it.

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
- **microphone mute** (the quick toggle, the bar's mic button, the mic-mute key) mutes every microphone at once — the built-in one, a headset, the echo-cancelled one — not only the default input, and a microphone connected while muted stays muted; unmuting turns them all back on;
- **the pages**, picked in the tab strip or with Ctrl+Page Up/Down: the **notification centre** with its [history](./notifications#history), a **calendar** with the day's events under the month (click a day to list its events, click it again to go back to today), the **to-do list** and a **pomodoro timer**.

**Jellyfin** (once Jellyfin is signed in on this computer; Settings → Panels → Right Sidebar → Jellyfin tab turns it off): _Up next_ — what you started, then the next episode of each series you follow — as wide thumbnails with how far you got, and _Recently added_ as posters, three a row. A click plays it in mpv on this computer (jellyfin-mpv-shim), where you stopped; a series (or an episode's list button) opens its episodes by season — watched ones ticked, the next one marked, _Play next_ on top — to pick one, the first say. How a play goes (starting, playing, or why it couldn't) shows at the bottom of the tab. The refresh button (or every 10 minutes while it shows) updates the list. While something plays on this computer's Jellyfin player, a bar at the bottom of the tab shows it with pause and a volume slider: the player's own volume (mpv's, not the system output's), remembered for the next film.

_Downloads, to watch offline_: the download arrow on a card, on a film's poster or on an episode's row keeps it on this computer (the button beside _Play next_: the whole season shown). The file is the server's own, not converted, with its external subtitles; downloads run in the background one at a time, outlive the shell, and go on from where they stopped. **Downloads**, at the top of the tab, lists what is here: size, how each download goes, the space used and free; a click plays one, the bin removes it (a second click confirms), the cross cancels a download. What is downloaded plays from its file in mpv, from where you stopped, with or without the server — when Jellyfin can't be reached, the tab shows your downloads by itself. How far you watched goes to Jellyfin the next time it answers, and what you watched elsewhere comes back (the later of the two wins). Files are in `~/.local/share/jellyfin-offline`. Watching along in the [Mesh](/nixbook-shell/mesh) goes through the server's player, not a downloaded copy.

The panel remembers the page you left it on, but opens on Notifications when something arrived while it was closed; from another page, a badge on the bell counts them. Settings → Panels → Right Sidebar turns off the pages other than Notifications.

It can be **pinned** too: the pin in its header, or Ctrl+P inside it (`nixbook-shell ipc call sidebarRight pin|unpin|togglePin`). Pinned, it stays open beside your windows, which make room for it, on the monitor it was pinned on, even across reboots; Escape and clicks elsewhere don't close it; **Mod+N** does, freeing its room, and Mod+N again opens it pinned, on its monitor (even after a restart). Notification popups still show while it is pinned, unless its Notifications page is the one in view.

### Left sidebar — Mod+Space

- the [AI chat](./ai-assistant);
- a **translator**.

It can be **pinned** (Ctrl+P) to stay open beside your windows — on the monitor it was pinned on, even across reboots — or extended (Ctrl+O). Pinned, **Mod+Space** still closes it, freeing its room, and Mod+Space again opens it pinned.

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
