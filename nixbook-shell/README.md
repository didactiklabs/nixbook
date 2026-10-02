# nixbook-shell

A Quickshell (QML) desktop shell for niri: bar, dock, sidebars,
launcher, notifications, lock screen, desktop widgets, an AI chat and a choice
of themes (see [Themes](#themes)): Material, the default (colours from the
wallpaper, Material 3 tonal elevation: surfaces are told apart by their tone
and a thin outline, with no shadows); Persona (Persona 5 Royal by default:
slanted black panels with bold Royal gold outlines, hard unblurred red offset
shadows, red accent slashes and halftone art); and Chiikawa (pastel light
palettes, bubbly corners, bouncy motion and an animated Momonga). None
blurs a shadow, which keeps them light on integrated GPUs. It started as a
fork of
[pctrade/end4-pC](https://github.com/pctrade/end4-pC), itself a fork of end-4's
illogical-impulse; it is now its own project, niri-only, with no upstream to
track (credits and licence in `src/`).

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
`settings toggle`, `search themeToggle`, `lock activate`, …).

## Login screen and loading screen

On NixOS, `nixbook-shell.greeter` (`greeter.nix`, part of
`nixosModules.default`) makes the login screen the shell's own: greetd running
`nixbook-shell greeter` (`src/greeter.qml`, `modules/ii/greeter/`, Quickshell's
greetd client) with one user's look — the theme and variant, the palette
(the theme's, or the one generated from the wallpaper), fonts, account picture
and cursor — drawn in that theme's style (a frosted card for Material, a
slanted frame with the variant's slash and halftone for Persona, the variant's
character peeking over a bubbly card for Chiikawa) under the date and a large
clock: the user with a greeting (the account pictures under the card, or Up /
Down, switch between the machine's accounts), the password (the eye shows it,
Esc clears it), PAM's cues (security key, fingerprint, further prompts such as
a one-time code) and the session pill (click or scroll to switch), which it
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
shell's Settings window (its search box, Ctrl+F, finds any setting or
section on any page and scrolls to it). Every key set in `programs.nixbook-shell.settings` is
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

## Desktop control for AI agents

`nixbook-desktop-mcp` (`scripts/desktop-mcp.py`, also `nixbook-shell mcp`)
lets an AI agent see and drive the desktop: list windows, workspaces and
apps; focus, move, resize, close windows; launch apps; take screenshots (a
monitor, a zoomed-in region, a window on screen), silently; save screenshots
and record the screen for the user (`screen_capture`: a monitor, region or
window to a file in `screenSnip.savePath` and/or the clipboard; recordings
of a monitor or region, with or without the desktop audio, through the
shell's recorder and its indicator: start, stop with the video's path,
status; never from the agent desktop); read the text on
screen (`read_screen`: OCR, each line with its position to click, ~150
tokens instead of a screenshot's ~1,250; `find` returns only the lines
containing the given text; `ocrLanguages`, `eng` by default); type, press
keys, click, drag, scroll, or several of these in one call (`run_steps`;
`type_text` pastes text with accents, punctuation or line breaks through
the clipboard, then puts the clipboard back: wtype's keymap swaps lose keys
in Chromium/Electron apps, and a line break would press Return);
the clipboard; the recent notifications as text (`notifications`: new chat
messages, mail…, by app, text or age; cheaper than a screenshot to see
whether someone answered); the shell's themes and variants (`list_themes`, `set_theme`:
"switch to Persona 3 Reload", "use the Usagi variant"; Nix-pinned ones stay
locked); the wallpaper (`set_wallpaper`: a JPEG, PNG, WebP or AVIF file
from a folder shared with agents, `ai.allowedFolders` or
`ai.writableFolders`, e.g. what the agent desktop's browser downloaded; the
palette follows); the desktop widgets without clicking them (`widget`: list, show or
hide any; arrange them: each widget's box per monitor (`layout`), move one
to a position on a monitor, hide it there, bring it to the front, or let it
follow the wallpaper's calm areas; read, add, edit and remove the notes
widget's notes and the to-do list's tasks; the timers' pomodoro, stopwatch,
countdown and alarm (set at a date and time, once or daily; dismiss,
snooze); the custom images: add one (a picture from a shared folder) on a
monitor, frame, style, move between monitors, remove; music recognition:
listen, the source, the songs found, through the shell's `widgets`,
`images`, `notes`, `todo`, `timers` and `musicRecognition` IPC targets, and
`region`'s recordStart/recordStop/recordStatus, which key bindings can call
too); the audio equalizer (`equalizer`: what's playing
with its Last.fm genre tags, then a preset or a 10-band curve and the
preamp, or Auto, which follows each song's genre; the `equalizer` IPC
target; its agent mode, `equalizer.agent` (the equalizer window's Agent
chip, Settings > Desktop agents), has a short Claude Code task with only
this tool tune the curve for each new song, `equalizer.agentModel`, Haiku
by default); the user's calendar, read-only
(`calendar`: the next event, the coming days, a given day, from DankCalendar
through the `calendar` IPC target); the shell's own IPC (sidebars, launcher, lock…);
notifications. It is a Model Context Protocol server, so
any agent that speaks MCP can use it:

```sh
claude mcp add desktop -- nixbook-desktop-mcp            # Claude Code
# opencode, Codex…: a local (stdio) server running
# `nixbook-desktop-mcp`
```

Any app's window can be read and driven through its accessibility tree,
what screen readers see (the `ui` tools, on by default): `ui_read` returns
the focused window's (or a given one's) buttons, fields, labels and list
items as numbered text lines, with their text and state, a few hundred
tokens where a screenshot costs ~1,250, and `ui_act` presses, toggles,
focuses or sets the text of one through the app itself, without
coordinates. After `type_text` and `press_keys` the result says which
element has the keyboard focus, so agents needn't screenshot to check where
the keys went. Only the windows niri lists and what is showing are read;
terminals, password managers and password prompts are refused, and password
fields never show their text. It needs the accessibility bus (nixbook's
`customNixOSModules.niri.accessibility`, on by default; NixOS otherwise sets
`NO_AT_BRIDGE=1`), and Firefox-based and Chromium/Electron apps only publish
their tree with `GNOME_ACCESSIBILITY=1` / `ACCESSIBILITY_ENABLED=1`, which
the module sets in the session (apps started before need a restart).

The **Desktop Control** bar widget (`desktopControl` in a bar layout) shows
it: a faint robot when idle, a pulsing one in the accent colour while an
agent acts (its calls within the last 20 s), a red hand when paused; its
tooltip names the last agent and tool. A click pauses every agent at once
(even between the steps of a `run_steps` batch), another allows them again;
it starts paused and remembers its position across reboots.
`nixbook-shell ipc call desktopControl toggle` (or `pause`, `resume`,
`status`) does the same from a key binding (nixbook binds it to
**Mod+Shift+Escape**); agents can't call that target.

Agents are slow mostly because every tool call is a model round trip, so
the tools save calls: `launch_app` waits for the app's window and says
which it is; every action's reply names the focused window; action tools
take `screenshot_after: true` to return a screenshot of the result in the
same call, once the screen stops changing (tiny captures of the monitor,
a caret or a clock aside; at most 2.5 s, or a fixed `wait_ms`), so a slow
page isn't caught half drawn and a quick one isn't waited for; `run_steps`
does up to 20 actions (keys, typing, clicks, waits) in one call, each
through the same guardrails (a step's `settle: true` waits the same way); screenshots are JPEG (a
fraction of a PNG's size; `screenshotFormat`, `screenshotQuality`). A
monitor screenshot sends only what changed since the agent's last one (up
to 3 crops, each with its own mapping), or just says nothing did: an image
costs the model about width × height / 750 tokens (~1,250 at 1280px, `screenshotMaxEdge`), and
most screenshots after an action change a small part (`full: true` sends
it all).

**Desktop memory**, so the next task is faster: agents keep notes of what
worked (`remember`: an app's shortcut, where a setting is, which app does
what; `run_steps` with `remember_as` saves the steps as a recipe; `recall`,
`forget`), and usage is counted as they work (apps launched, layouts
restored, tools used). `launch_app` learns aliases: a name that failed, then
the app that worked (e.g. "discord" then Vesktop), resolves directly next
time. Only the right part reaches a model, to keep its context small:

- when an agent connects, a digest (at most `memoryPromptChars`, 1500)
  carries the aliases and most used apps, the full text of the notes about
  the task — the AI chat passes the user's message; other agents get the
  most used notes — and the other notes by topic only ("wifi (3)"); agents
  are told to look there when given a task and to `recall` the topics that
  match it before acting;
- notes are linked to the apps they are about (the topic names the app,
  an alias, or the keywords of an app used before; apps used before win),
  and come with the reply of the action that reaches that app (launching
  or focusing it), once per session; so do the notes whose topic, its
  generic words aside ("search", "settings", "tab"…), is named by the
  focused window's title or the text an action types (typing "furnished
  apartments in tokyo" brings the "apartment search" note);
- `recall` ranks notes by the words of a question (topic first) and returns
  the best five; without a question, the list of topics;
- a note counts as used each time it goes to an agent (recalled, about its
  task, or just in time), so the useful ones rank first and are kept at the
  cap;
- `remember` answers with the notes already on its topic, so the agent
  merges them into one (`remember` with an `id`) instead of piling up
  near-duplicates.

With 40 notes, the digest went from about 745 tokens (and the notes about
the task could be cut off) to about 165, with those notes in full. It is
labelled as hints written by agents, never the user's instructions; the
instructions ask agents to save what they learned.
It lives in `~/.local/state/nixbook-shell/desktop-memory.json` (private);
**Settings → Desktop agents** shows the notes (delete any), the aliases and
usage, clears them, and pauses desktop control. `nixbook-desktop-mcp memory`
shows, clears or prints the digest; the `memory` tool group
(`desktopMcp.settings.tools`) turns it off; `memoryPromptChars` and
`memoryMaxNotes` size it.

**Window layouts**: `save_layout` remembers where every window is (monitor,
workspace, column and its width, or floating position and size, and the app
that opens it) under a name; `restore_layout` puts them back in one call,
starting the apps that were closed. The same layouts are yours in the shell,
where the agents' pause doesn't apply: **Mod+G** opens the launcher as a
layout picker (the `#` prefix: pick one to restore it, or type a new name to
save the windows as they are), the desktop's right-click menu has a Window
layouts submenu, and Settings → Window layouts lists them to restore,
update, rename or delete. Key bindings can also call the `layouts` IPC target
(`cycle`, `saveCurrent`, `restoreNumber N`, `restore NAME`, `save NAME`;
agents can't call it), and scripts `nixbook-desktop-mcp layout …`.
They live in `~/.local/state/nixbook-shell/layouts/`. Restored with a
monitor unplugged, the windows saved on it stay where niri moved them (with
their workspace, back on the monitor when it's plugged in again), and the
layout can't be overwritten until the monitor is back: save under another name.
Settings → Window layouts → _Close the other windows when restoring_
(`windowLayouts.closeOthers`, off by default; `layout restore|cycle
--close-others`) makes your restores also close the windows the layout
doesn't have, as their close button would. Not while a monitor of the layout
is unplugged, and never the agents' `restore_layout`.

**Claude in the side panel**: when Claude Code is installed (`claude` on the
PATH, in `~/.local/bin` or a Nix profile), the AI chat offers a **Claude**
model (`/model claude`) that runs on your own Claude login, no API key. It is
set up in **Settings → Desktop agents → Claude in the side panel**: whether
Claude Code was found (and its command, if elsewhere), the model (Sonnet by
default, or Opus, Haiku, Claude Code's own) and its thinking effort (low by
default: driving the desktop is many short steps, each waiting on the
model), whether it may search and read the web, the folders it
may read, and a button to use it in the panel (the `ai.claudeCode.*` and
`ai.allowedFolders` settings; Nix can pin them like any other). Claude
Code (`claude -p`) keeps running between messages, each one a line on its
stdin, so a message doesn't wait ~2 s for it and the desktop MCP server to
start: it starts when you open the panel on Claude, again (resuming the
conversation's session) when a setting or an attached file changes its
command line, and closes after 15 minutes unused; Stop interrupts the answer
and keeps it. It runs with the desktop MCP server attached (its guardrails,
the pause button and the memory apply as always; tool `none` leaves it out)
and only the built-in tools in `ai.claudeCode.allowedTools` (web search and
fetch); running commands and editing files are refused. **It reads none of
your files** unless you allow it: **Folders AI agents may read**
(`ai.allowedFolders`, none by default) become its `--add-dir` working
directories, read-only, and a file attached to a message is readable alone
(`Read(//that/file)`). Without any, it has no file tools at all
(`--disallowedTools Read Glob Grep`). **Folders the agents' desktop may write**
(`ai.writableFolders`, none by default) are bound read-write into the agent
desktop's sandbox (made if missing; never the whole home or `/`), and the
first is its apps' Downloads folder (`XDG_DOWNLOAD_DIR` in its home), so an
agent can download a file in its own browser and use it on your side, a
wallpaper for instance; Claude can read them, not write them, and is told
where downloads land. It runs in an empty directory of its own
(`~/.local/share/nixbook-shell/assistant`, not your home) and without your
`~/.claude` settings (`--setting-sources project`: allow rules you set for your
own Claude Code sessions don't apply), and any other read is denied (`-p`
can't ask). Claude Code in a terminal, or any other MCP client, follows its
own permissions.
**Use your claude.ai connectors** (`ai.claudeCode.connectors`, off by
default) also gives it the connectors of your Claude account (Gmail,
Calendar, Drive… as connected on claude.ai, found with `claude mcp list`),
every tool of each allowed without asking; it then drops
`--strict-mcp-config` and keeps their tools behind ToolSearch.
Replies stream in, each tool call shows with its result in a collapsible
block, and the send button stops the answer (and what Claude is doing), as
does `/stop`. Sonnet is faster than Opus for desktop tasks.

The side panel's other model is the offline **Config assistant** (the
default), which answers from this machine's configuration without any AI.

Over stdio (above) nothing listens anywhere: the agent starts the server
and talks to it through a pipe. For an agent that can only reach a URL,
`desktopMcp.http.enable` runs it as the `nixbook-desktop-mcp` user service
at `http://127.0.0.1:7823/mcp`:

- bound to 127.0.0.1 only: loopback traffic never leaves the machine and
  isn't filtered by the firewall, so no port is opened and nothing on the
  network can reach it;
- a bearer token (`Authorization: Bearer $(nixbook-desktop-mcp token)`),
  kept in `$XDG_RUNTIME_DIR/nixbook-desktop-mcp/token` (0600);
- the connecting process must belong to the same user (checked in
  `/proc/net/tcp`), so other accounts are refused even with the token;
- the Host and Origin headers must be loopback ones (no DNS rebinding from
  a web page); the unit allows only Unix and IPv4 sockets.

Guardrails, whatever the transport:

- no tool runs a command: apps start from their `.desktop` entry only (no
  arguments, no terminal apps), niri actions and IPC calls are a fixed,
  validated set, the `session`, `nixManaged` and `desktopControl` IPC
  targets are off limits;
- no keyboard or pointer input while the focused window is a terminal, a
  password manager or a password prompt (`inputDenyApps`,
  `inputDenyTitles`), no Super combinations (compositor bindings) or
  Ctrl+Alt+Delete/F-keys;
- the bar widget, `nixbook-desktop-mcp pause` (or `toggle`) stops every
  tool (for every agent, until `resume`): bind it to a key as a panic button.
  Desktop control starts paused: agents may act only while
  `~/.local/state/nixbook-shell/desktop-control-allowed` exists, which
  `resume` creates and `pause` removes, so the choice survives a reboot and a
  fresh install (or wiped state) stays paused until you allow it. Without a
  private `$XDG_RUNTIME_DIR` nothing runs;
- at most 120 actions a minute, 4000 characters per typed text or task
  (100000 per note: notes go to the shell through a private file, not its
  IPC, which large messages can wedge), a notification
  when an agent starts driving the desktop (again after 5 idle minutes);
- every call is logged to `~/.local/state/nixbook-shell/desktop-mcp.log`
  (typed and copied text by length only).

`programs.nixbook-shell.desktopMcp.settings` (written to
`~/.config/nixbook-shell/desktop-mcp.json`) turns tool groups off (`tools`:
`observe`, `screen`, `windows`, `input`, `shell`) and tunes the rest;
`nixbook-desktop-mcp config` prints what applies. Keyboard input goes
through `wtype` (Wayland virtual keyboard). The pointer goes through niri's
virtual pointer (wlr-virtual-pointer, spoken by a small Wayland client in the
script): absolute desktop coordinates without pointer acceleration, so
clicks, drags and scrolls land on the exact logical pixel, on any monitor
and scale; ydotool (approximate) is only a fallback where the protocol is
missing, and `get_status` says which one is in use. Monitor and `region`
screenshots (a region is captured at the monitor's full resolution, to zoom
in on small targets) return a `mapping` that the pointer tools take as
`screenshot`, so an agent clicks in image pixels without converting
coordinates itself. Screenshots are taken with grim, silently: a window's
is cropped from the screen (a floating window exactly; a tiled one comes
with its monitor, since niri gives no position for tiled windows). A window
off screen is only captured through niri with `offscreen: true`, which the
tool tells agents to avoid: niri copies its captures to the clipboard and
notifies (the previous clipboard is put back, but cliphist records it).

### A desktop of their own

So an agent can work while you work, it can be given its own desktop:
`nixbook-desktop-mcp desktop agent` (or `Mod+Shift+A`, which toggles; also
right-clicking the Desktop Control bar widget, the desktop menu's
"Assistant's desktop" entry and Settings > Desktop agents) gives
them `nixbook-agent-desktop` (`scripts/agent-desktop.sh`, the user service of
the same name): a nested niri, shown on your desktop as a window called
"Assistant's desktop" (app id `nixbook-agent-desktop`). It's never open
empty: it opens (beside your work, without taking the focus, with a
notification) when an agent starts an app, and closes by itself once the
agent's last app is gone (the launcher watches it: 10 s without a window). Every
agent's tools then act there: its own pointer,
keyboard focus, clipboard and windows, so nothing the agent does moves your
windows, takes your focus or types into what you're typing in.

To you it's one more app window: nothing is on the agent's desktop but the
one app it works in, fullscreen, and kept so even when the app asks to
leave it (Zen and Firefox restore their window size on start; a browser
may hide its tabs and address bar then, so the agents are told to use its
shortcuts): no bar, no focus ring or
borders, no hot corner, and `launch_app` closes the agent's previous app
when it starts another (that app's own dialogs stay), so there's never a
layout inside. The bar widget shows a window icon beside its robot while
agents are on their own desktop (red once you've closed it).

The window is a view, not a way in: its niri drops your clicks and keys
(`niri-winit-agent-window.patch`, which also names the window and keeps
its apps fullscreen; the agent's
niri only: yours stays the cached nixpkgs package, this one builds
locally), so you watch it work, and move, resize or send the window
elsewhere like any other (switching to it while it's open focuses it, so
niri scrolls it into view). To use it yourself for a moment (log the agent's
browser into a site, say), take it over: `Mod+Ctrl+A`, the desktop menu's
"Use it myself", Settings, or `desktop interact on|off|toggle`. Your clicks
and keys then reach it, and the agent's window and input tools are refused
until you give it back (it can still take screenshots); it's off again
after a restart. **Closing the window yourself stops the agent**: its
tools are refused ("the user closed your desktop") until you switch it on
again (the launcher tells your closing from its own: it marks
`~/.local/state/nixbook-shell/agent-desktop-stopped`). `desktop user` brings the agents back to
your desktop, `desktop stop` closes theirs, `desktop status` says which is
in use (also `get_status`); the choice survives a reboot. An agent already
at work when you switch is told on its next tool reply ("Desktop switched
by the user: …", with what the desktop it's now on means for it), once per
MCP session, since its instructions only said where it was when it connected.

Its apps are the agent's, not yours, and sandboxed (bubblewrap): **they see
none of your files**. Their home is `~/.local/share/nixbook-shell/agent-home`
(their own browser profiles, history and logins); your GTK/Qt/font settings
are visible read-only so apps look the same, the **Folders AI agents may
read** read-only (from its next start), and nothing else of your home, of
/mnt, /media or other homes, nor the system's logs and state (`/var/log`,
`/var/lib`) or `/etc/nixos`. They get their own D-Bus session (no keyring,
portals or notifications of yours; a browser you already have open still
starts a copy of its own there), no system bus, none of your runtime sockets
(no session bus, audio, X11, desktop-mcp's token), and their own process
namespace (none of your processes to see or attach to). **Your desktop
only through a restricted connection**: its niri reaches yours through a
socket made with security-context-v1 (`nixbook-wayland-security-context`,
`scripts/wayland-security-context.py`; the way Flatpak does it), so neither
it nor anything in the sandbox can capture your screen, type or click into
it, read your clipboard or list your windows; it can only show its window
(and take your clicks and keys while you take it over). ydotoold's socket,
which types into your desktop, is hidden whatever the settings. Two
switches in Settings > Desktop agents (`ai.agentDesktop`), both on, from
its next start:

- **Hide the system's services from their apps** (`hideSystemSockets`):
  `/run` is empty but for what apps need (the system's programs, graphics
  drivers, name lookups), so no system daemon's socket is reachable;
- **Keep their apps off this computer's local services**
  (`privateNetwork`): their own network (pasta): the internet and your LAN
  through your connection, but not what listens on this computer
  (`127.0.0.1`: a dev server, the printer and Sunshine pages) nor its
  abstract sockets (X11); DNS goes through pasta. Off, their browser can
  open those too. If pasta can't start, the desktop doesn't open (it
  never falls back to your network) and a notification says so.

What the
sandbox may change is its home and the nested session's runtime directory;
the launcher's own files (where its sockets are, the take-over flag) are
read-only to it, and it watches the session from outside, so an app can't
fake "closed because empty" to keep closing the window from stopping the
agent. Log the agent's browser into an account only if you want it to use
that account. File choosers are GTK's own there (the portal's would open on
your desktop).

The shell tools still act on your desktop: `widget` (notes, to-do list,
timers), `calendar`, `notify`, `set_theme` reach your shell over its IPC,
whichever desktop the agent works on. So an agent can, say, look for flats
in its browser and write what it found into your notes widget. Only the
generic `shell_ipc` is refused from the agent desktop: the panels it opens
(sidebars, launcher, lock screen) would appear on your screen. The agents
are told all this when they connect.

Why not two seats in one niri (two pointers and keyboards on your
desktop)? niri has one focus and one view per workspace, and most apps
ignore input from a second Wayland seat (Chromium and Electron entirely,
kitty too): a nested compositor needs no niri patch and works with every app.

## Look and feel

The type is Google Sans Flex (main, titles, numbers), with Space Grotesk for
the desktop clock and Readex Pro for reading in the AI chat
(`appearance.fonts`): `fonts.nix` ships them (the Home Manager module
installs them, the login screen gets them too), so nothing falls back to
the system's sans-serif.

The bar says what the pointer can do on each widget while it hovers it
(`BarPointerCue`, put on every popup's widget by `StyledPopup`):

| Cue                                                  | Meaning                 |
| ---------------------------------------------------- | ----------------------- |
| accent notch on the side the popup opens from        | hovering shows a popup  |
| hand cursor and a soft highlight (or its own ripple) | clicking does something |
| both                                                 | both                    |
| neither                                              | nothing happens         |

A new clickable bar widget sets `cursorShape: Qt.PointingHandCursor` (a
`StyledPopup` on it then adds the highlight too) or adds
`BarPointerCue { target: <its MouseArea> }` when it has no popup and no hover
state of its own; a hover-only one keeps the arrow.

## Themes

The theme is `appearance.theme` — Settings → Appearance → Theme, the
desktop menu's Theme submenu, or the launcher's theme mode (the
`search.prefix.themes` prefix, `@`, or `nixbook-shell ipc call search
themeToggle`: every theme and variant, type to filter, Enter applies) — and each theme with variants keeps its own
`appearance.<theme>.variant`, so switching theme and back keeps the variant:

| Theme       | Variants                                         | Own settings (`appearance.<theme>.*`)              |
| ----------- | ------------------------------------------------ | -------------------------------------------------- |
| `material`  | —                                                | —                                                  |
| `persona`   | `p5` (Royal), `p3r` (3 Reload), `p4` (4 Revival) | `palette`, `motion`, `shapes`, `halftone`, `fonts` |
| `chiikawa`  | `chiikawa` (default), `usagi`, `momonga`         | `palette`, `motion`, `shapes`, `fonts`, `mascot`   |
| `cyberpunk` | `yellow` (default), `red`                        | `palette`, `motion`, `shapes`, `fonts`, `glitch`   |

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
the first time: the Chiikawa and Cyberpunk ones; for the lock and login screens, nothing:
they follow the desktop, then the lock screen), and a wallpaper picked while
in a variant becomes that variant's. Settings → Appearance → Theme sets or
unsets all of them at once, in a table of every variant. Each theme has its own sounds too (`sounds` in `themes.json`: the
notification chime and the critical sound — Persona 5's by default, the
characters' own in Chiikawa, a digital blip and a glitch alarm in
Cyberpunk 2077); a file set in the settings wins. Important
notifications (critical ones, and those the cut-in rules pick:
Settings → Bar → Notifications → Cut-ins) get the theme's cut-in: the
full-screen Persona one, the Chiikawa character popping up with a speech
bubble (`ChiikawaAlert.qml`), or an incoming holocall glitching in — a
chamfered HUD panel with an RGB split, scanlines and the message typed out
(`CyberpunkCutIn.qml`; `appearance.cyberpunk.glitch = false` keeps it
steady).

Before `appearance.theme` the Persona style was the switch
`appearance.persona.enable`. It still works: a `config.json` holding it is
migrated to `theme = "persona"` when the shell loads it, and the Nix option is
translated to `appearance.theme` with a deprecation warning.

Under niri the window open/close animation can follow the theme too:
`services/NiriThemeAnimations.qml` fills
`~/.config/niri/nixbook-shell-animations.kdl.in` (its `@ACCENT@` and `@INK@`
GLSL vec3s) with the palette's primary and ink colours and writes
`nixbook-shell-animations.kdl` next to it whenever they change; a niri config
that includes that file (`include optional=true`, last) is recoloured live.
nixbook's `homeManagerModules/niri` ships the template (Persona slash) and
the include; without a template nothing is written.

### App colours

Other apps can follow the palette the shell shows (the wallpaper's or the
theme variant's), each switched on in Settings → Appearance → Color
generation, under Apps (`appearance.wallpaperTheming.apps.*`; switching one
off undoes its setup). `services/AppTheming.qml` hands the palette to
`scripts/colors/apply-app-colors.sh`, which renders the templates in
`scripts/colors/app-templates/` and gets them to the apps:

| App         | How the running app gets the new colours                                                                                                                                                        |
| ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Qt & KDE    | Live: kdeglobals + a palette-changed signal; Qt apps read the palette through qt6ct/qt5ct, set up by `programs.nixbook-shell.appTheming.qt.enable`                                              |
| Vesktop     | Live: its themes folder                                                                                                                                                                         |
| Zen Browser | At startup only (`zen-theme.py`): the CSS is imported by each profile's `userChrome.css`; while Zen runs, a notification offers to restart it (SIGTERM, a normal quit; the session is restored) |

The palette is made readable before it is rendered
(`render-app-colors.py`): a theme variant's colours are picked for the
shell's look, and a pastel primary that works as a fill (Chiikawa's Momonga)
is unreadable as the link, tab or icon colour the apps use it for. Text roles
(`on_surface`, `on_surface_variant`, `primary`, `secondary`, `tertiary`,
`error`; `outline` at 3:1) get at least 4.5:1 against every surface, and
each `on_<role>` against its `<role>`, by moving only their lightness; colours
that already read are untouched (Material's generated palettes are). Besides
matugen's `{{colors.<role>.default.hex}}`, templates can use `{{mode}}`
(`light`/`dark`). Zen's template overrides what its workspace theme sets
inline on the window and on each `zen-workspace` (`--toolbox-textcolor`,
`--zen-primary-color`, `color-scheme`), which otherwise kept its own
light/dark text over the palette's background; web pages keep Zen's own
light/dark setting.

The Qt/KDE scheme draws every text colour of its selection set
(`[Colors:Selection]`) in `on_primary`, since it sits on the `primary`
selection fill, where the surface text roles can be the same colour (about
1:1 on Momonga). A KDE app can also pin a scheme of its own in its rc file
(`[UiSettings] ColorScheme`, written by Dolphin's View → Color Scheme menu, or
DankMaterialShell's `DankMatugen`), which wins over kdeglobals; mixed with the
palette qt6ct applies, a dark pinned scheme drew dark text on dark rows. While
the Qt switch is on, `apply-kde-colors.py --unpin` removes such pins from
`~/.config/*rc`, so the app follows the shell (restart it once).

Slack and YouTube Music are deliberately not themed: Slack looked bad
recoloured, and YouTube Music is dark-only (its styles hard-code white and
grey text in over a thousand rules). Their old switches
(`appearance.wallpaperTheming.apps.slack` / `.youtubeMusic`) are removed keys.

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

The Chiikawa character is an animated GIF of Momonga
(`src/assets/chiikawa/momonga.gif`), the same for every variant; the rest of
its art (the sidebar patterns and the wallpapers, the GIF's first frame on a
hill) is drawn by `src/assets/chiikawa/generate.py` from the variants'
palettes; rerun it after changing them. Its sounds are synthesized when the package is built
(`src/assets/chiikawa/sounds.py`, no audio file in git). The Cyberpunk 2077
theme works the same way: `src/assets/cyberpunk/generate.py` draws its
wallpapers from the palettes, `sounds.py` synthesizes its sounds at build
time, and its face (Rajdhani) ships in `fonts.nix`.

Settings that did nothing were removed (`lib.nix` `removedKeys`: the parallax
options, `bar.topLeftIcon`, the settings window border…); an old Nix
configuration setting one still evaluates, with a warning, and the value is
ignored.

## Layout

| Path               | What                                                                                                                       |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------- |
| `default.nix`      | entry point (`package`, `homeManagerModules.default`, `lib`)                                                               |
| `package.nix`      | the launcher: runtime `PATH`, QML import path, `config` CLI                                                                |
| `dankcalendar.nix` | DankCalendar (`dcal`), the calendar and task sync, from `npins/`                                                           |
| `qml.nix`          | the QML tree as installed (store-path fixups, Persona, Chiikawa and Cyberpunk art and sounds, emoji list)                  |
| `fonts.nix`        | the faces `appearance.fonts` names that nixpkgs lacks (Google Sans Flex, Space Grotesk, Rajdhani)                          |
| `quickshell.nix`   | Quickshell from `quickshellSrc` plus `patches/`                                                                            |
| `lib.nix`          | typed settings options generated from `builtin-defaults.json`                                                              |
| `hm-module.nix`    | the Home Manager module `programs.nixbook-shell`                                                                           |
| `nixos-module.nix` | optional NixOS module: the system's toggles for the assistant                                                              |
| `greeter.nix`      | the login screen (`nixbook-shell.greeter`, imported by it)                                                                 |
| `toggles.nix`      | discovers the `enable` toggles from an options tree                                                                        |
| `scripts/`         | `config` CLI, its jq library, assistant facts, Anthropic usage, login screen theme, emoji list, desktop control MCP server |
| `npins/`           | default nixpkgs, quickshell, dankcalendar (+ flake-compat) pins                                                            |
| `src/`             | the QML tree                                                                                                               |
| `tests/`           | script tests, lib unit tests, the self-containment check                                                                   |

## Tests

```sh
bash tests/scripts.sh
bash tests/desktop-mcp.sh    # the desktop control MCP server, against stub niri/wtype/grim… and a fake compositor
nix-instantiate --eval --strict --json --expr 'import ./tests/lib.nix { }'   # []
nix-instantiate --eval --strict --read-write-mode tests/standalone.nix \
  --arg homeManager '<home-manager checkout>'                                  # "ok"
```
