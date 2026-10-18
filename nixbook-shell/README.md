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
another quickshell pin; `withTailscale = false` / `withNetbird = false` leave
that VPN CLI out of the shell's PATH — the module's default package does so
under NixOS when the system doesn't enable `services.tailscale` /
`services.netbird`) gives:

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

The accounts (nixbook-accounts, see "Accounts, contacts, tasks and
calendars" below) keep every calendar surface in sync
(`src/services/CalendarEvents.qml` reads the events around the month shown,
recurring series expanded by nixbook-accounts):

- events: dots on the days of the sidebar, desktop and bar clock calendars,
  the next events in the bar clock popup, a day's events when you click it in
  the sidebar (with an "add event" button); clicking the bar clock (right
  click: sync) or a day of the desktop calendar opens the **Calendar**
  window (`src/modules/ii/calendarApp/`; launcher entry "Calendar",
  `nixbook-shell ipc call calendar launch|open YYYY-MM-DD`): the month (each
  day's events, "+N more"), the selected day's events, and the event editor
  (title, all day, start and end, calendar, repeat, reminders, place, notes;
  a recurring event's occurrence alone or all of them, all of them moving
  as that occurrence did; read-only calendars shown, not edited); Ctrl+N
  new, T today, Page Up/Down, F5 sync. The shell syncs every
  `calendar.refreshMinutes` (30) and rereads the local copy whenever it
  changes, keeping the same data (no redraw) when nothing changed; the
  refresh button in the sidebar calendar's header syncs now;
- the next events: the "Next Event" bar widget (`nextEvent` in a bar layout:
  "in 12 min" and the title, the following ones on hover; click joins the
  meeting when it starts within 10 minutes, else opens the Calendar) and
  desktop widget (`background.widgets.nextEvent`: the next one large with a
  Join button, the three after it);
- tasks: the to-do list (sidebar, desktop widget, bar clock popup, the
  launcher's "add task") is your accounts' tasks (Google Tasks…) once one
  is added (nixbook-accounts, see below), a local list before that
  (`src/services/Todo.qml`). The
  **Tasks** window (`src/modules/ii/tasks/`, Google Tasks-like; launcher entry
  "Tasks", `nixbook-shell ipc call tasks open|toggle|close`) shows each list
  as a column (subtasks under their parent, "Completed" folded) and a
  "Deadlines" column of every dated task (Overdue, Today, Tomorrow, Next 7
  days, Later); a task opens its details (title, notes, deadline, list:
  Google moves it, subtasks and id kept), "Create"
  (Ctrl+N) adds one to any list with a deadline. The desktop to-do widget
  lists open tasks by deadline (overdue in red), opens the window on a click,
  adds tasks to any list with a deadline, and resizes from its corner
  (`background.widgets.todo.width`/`height`, per monitor). The lists
  themselves are made, renamed and deleted from the window ("New list", ⋮ on
  a list; deleting one deletes its tasks, after a confirmation): Google's
  through nixbook-accounts, the local ones in `todo-lists.json` next to
  `todo.json` (the first stays).
  What Google refuses (its default list can't be deleted) shows in a
  message bar;
- notes: the desktop notes widget's notes (`src/services/Notes.qml`) also
  open in the **Notes** window (`src/modules/ii/notesApp/`; launcher entry
  "Notes", `nixbook-shell ipc call notes launch`, or `notes open <id>`): the
  notes on the left (search, pinned first, then the latest edited), the
  selected one in a full editor saved as you type (an emptied note is
  dropped when you leave it; Delete has Undo), Ctrl+N new, Ctrl+F search,
  Ctrl+P pin; narrow, the list then the note. The widget lists them in the
  same order and opens a note, its title or ⤢ in the window; "+" still
  jots one down in the quick floating editor. Agents' changes (the `widget`
  tool's notes, which can also `open` one) show live;
- reminders: the shell's own notifications (`src/services/CalendarReminders.qml`,
  app "Calendar", through notify-send: at each reminder time of an event, its
  own or its calendar's; Join, Snooze 5 min, Open), shown by the shell's
  notification server and silenced by Do Not Disturb; the ones shown are
  remembered (`calendar-reminders.json` in the state directory), one missed
  while the shell wasn't running shows if at most 10 minutes late.
  Other copies of the same reminder (the phone's calendar app mirrored by KDE
  Connect, Google Calendar in the browser) can be made quiet with
  `notifications.quiet` (Settings → Notifications → Quiet: apps and rules, in
  the cut-in rule syntax, whose notifications don't pop up, cut in or chime
  but still reach the notification centre and the history).

The calendar widgets have the same account button: "Add an account" until
one is (the accounts window), then "Open the calendar"; right click syncs
now. The to-do widgets' button syncs the tasks. The desktop menu's widget list scrolls when it is
taller than the screen. The assistant answers "how do I sync my Google
calendar?" and the like (`assistant.howTo.calendar*`).

### Accounts, contacts, tasks and calendars

`nixbook-accounts` (`accounts/`, Go, `accounts.nix`; on the shell's and the
desktop MCP server's PATH, and installed) is the shell's accounts backend. A
built-in account, `local` ("This computer", `internal/local`), keeps
contacts, task lists and calendars on this computer only, in
`$XDG_DATA_HOME/nixbook-accounts/local/` (the data, not a copy: a sync
rereads it); always there, last, so new things go to a synced account when
there is one; it can't be removed. Todo.qml moves its former local list
(`todo.json`) into it once (files kept as .bak).
the user's accounts, each signed in once, and their contacts and tasks
merged. Providers register with each service (`internal/contacts`,
`internal/tasks`, `internal/calendar`): Google (`internal/google`: the user's own OAuth client,
Google Cloud "Desktop app", since DankCalendar's built-in one is for
DankCalendar only; one consent covering contacts, tasks and calendars, a
token per account) and CalDAV/CardDAV servers (`internal/dav`, emersion's
go-webdav: presets for iCloud, Fastmail, Nextcloud, or any server; a user
name and an app password, checked on the server when added; address books
as contacts, synced with sync-collection; the calendars that hold to-dos as
task lists; the calendars that hold events, read within a window around
now; labels as vCard categories, the star as the "Starred" category). The
calendar copy keeps events as their providers do (a series once, with its
RRULE/EXDATE lines, its changed or cancelled occurrences beside it) and
`calendar events --from --to` expands them (rrule-go), so every provider's
recurrences read alike. The accounts are in
`$XDG_STATE_HOME/nixbook-accounts/accounts.json` (no secrets: client and
tokens in the keyring, `secret-tool`). Each service keeps one merged copy
there (`contacts.json`, `tasks.json`; a section per account, with its sync
state), ids being global (`<account>:<provider's id>`, e.g.
`google-1:c123`): changes go to their account's provider first and its
answer lands in the copy, which the shell watches (a vCard's inline
photo as a file in `$XDG_STATE_HOME/nixbook-accounts/photos/`, named by
its content; `set_photo` takes an image file, made a JPEG of at most 720
px). `nixbook-accounts
--help` lists the commands (`setup google`, `add google`, `add dav`,
`remove`, `status`, `contacts sync|list|get|apply`, `tasks
sync|list|apply`, `calendar sync|calendars|events|apply`); `tests/accounts.sh` runs them against fake Google APIs
(`tests/fake-google.py`, data per signed-in user), two accounts included,
and `tests/dav.sh` against a real CalDAV/CardDAV server (Radicale).
`src/services/Accounts.qml` holds the accounts (status, Google's setup,
adding one, removing one; one command lane per service, so a contacts sync
doesn't hold up a ticked task); the accounts window
(`src/modules/ii/accounts/`, `nixbook-shell ipc call accounts launch`) lists
them and adds one (Google's one-time client setup first; a DAV server's
form, the password given to nixbook-accounts on stdin); the task widgets'
account button and the apps open it.

- contacts: `src/services/Contacts.qml` reads the copy and calls
  `nixbook-accounts` (a sync on first use, every 30 minutes, on demand).
  The **Contacts** window (`src/modules/ii/contactsApp/`; launcher entry
  "Contacts", `nixbook-shell ipc call contacts launch|open <id>|toggle|close|sync`)
  shows the accounts page until one is added, then lists the contacts
  (search, All/Starred/account/label chips, starred first, then A–Z) and
  shows the selected one (its account, write, call, message, map, copy;
  birthday and age) or edits it: only the fields changed go to the
  account, the rest of the contact stays; a new one goes to the account
  picked. The desktop widget (`background.widgets.contacts`) shows the
  birthdays of the next two weeks and the starred contacts; one opens the
  window on them. Agents use the MCP server's `contacts` tool (list, get,
  create in an account, update, star, delete, labels, sync, open, batch).
- tasks: `src/services/Todo.qml` (above) reads the tasks copy and changes
  tasks and lists through `nixbook-accounts tasks apply` (a sync at start,
  every 10 minutes, when the Tasks window opens, and from the widgets'
  account button); with several accounts a list's name says its account
  ("My Tasks · work"), and tasks move between lists of one account.

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
countdown (it rings until dismissed, like the alarm) and alarm (set at a
date and time, once or daily; dismiss, snooze); the custom images: add one (a picture from a shared folder) on a
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
by default); the user's calendars (`calendar`: the next event, the coming
days, a given day through the `calendar` IPC target; the calendars, and
creating, changing and deleting events, an occurrence or a whole series,
through nixbook-accounts); the user's contacts (`contacts`); the to-do lists, all of them (`tasks`:
every list and task with its notes, deadline, overdue state and parent;
create in any list with notes and a deadline, rename, re-date, move to
another list, complete, delete, clear the completed ones, open the Tasks
window on a task; create, rename and delete the lists themselves; and up to
50 of these in one `batch` to reorganize; the
`todo` IPC target's query/apply, which pass JSON through private transfer
files like the notes'); the shell's own IPC (sidebars, launcher, lock…);
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
coordinates. `ui_wait` waits until an element shows (a page loaded, a
dialog opened) or is gone, reading the window again on each change the app
reports, instead of a fixed wait and a screenshot. `ui_act` also takes a
`target`, an element's name, instead of an `index`: one call instead of
`ui_read` then `ui_act`. A control acted on (button, tab, menu item, check
box… with a name of 40 characters at most; never list items, links, texts
or cells, whose names are content) is learned per app with its place in
the window's tree (`targets` in the desktop memory, 40 per app, 60 apps):
next time it's reached there directly, after checking its role, name and
that it's showing, with no walk through the tree; a stale place falls back
to a search and is learned again, and several elements with that name are
listed for an `index`. The names learned in an app come with the agent's
first action there. Learned from agents' actions only, never the user's
input. Agents are told to look
through these before taking a screenshot. On the agent desktop they read its
apps through its own accessibility bus (its sandbox's), never yours. After `type_text` and `press_keys` the result says which
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
- `recall` ranks notes by the words of a question (topic first, then the
  keywords the memory pass gave them) and returns the best five; without a
  question, the list of topics and the reminders;
- `remember` answers with the notes already on its topic, so the agent
  merges them into one (`remember` with an `id`) instead of piling up
  near-duplicates.

It learns as a person does, in plain code (no model call, no token), from
what agents do — an **episode** is one task, ending at the next one, after
10 idle minutes or when the client leaves:

- a note is judged by its task's outcome: given for it (about the task, the
  app reached, or recalled) and the actions in its apps went well, it
  helped (`ok`, and a trace); most of them failed, it failed (`fail`,
  flagged to the next agent once it fails more than it helped); being shown
  is only counted (`shown`), and a note the agent rewrote is judged next time;
- notes rank by ACT-R's base-level activation, ln Σ tⱼ^-0.5 over the times
  they helped (spaced: uses within an hour count once), plus what they
  proved; unasked, the digest gives only notes above a threshold;
- unused 90 days (180 if it helped, 365 if it helped 3 times or more), a
  note moves to the archive (`archive`, 200 kept): `recall` finds it there
  and brings it back; at the cap the weakest go there too;
- each note has its `source`: `seen` working, said by the `user`, `read` in
  content (tentative, flagged, never given unasked, can't say always/never/
  must) or `inferred` by the memory pass; no note but the user's can tell
  agents to ignore their rules or send something somewhere; a replaced text
  is kept as `was`;
- recipes: `run_steps` `vars` fill `{name}` placeholders, and with
  `remember_as` the recipe keeps them (the same topic replaces it);
  `run_recipe` runs one in a call (its steps never go through the model
  again), counting the days it worked; worked on 3 days, it is a macro,
  offered in one line; a failing step demotes it (`failStep`);
- `remind` keeps a reminder with its cue (an app, words in a window's
  title, a time; once, or daily with `repeat`): the shell
  (`services/MemoryReminders.qml`) checks them on focus and title changes
  and every half minute, notifies (app "Reminder") and fires them
  (`memory fire ID`).

Model calls only where they pay, in the background, by Claude Code with no
tools (`memoryModel`, Haiku; `memoryClaude`; `memoryLearn = false` turns
them off): an episode new to the memory (no note helped, no recipe ran)
that went well and took work (8 actions, or 2 failures) goes to `memory
learn`, which sees the request, the actions in short (typed text as its
length only) and the notes on those apps, and may save notes or recipes
(`inferred`, tentative until they help; recipes typing only placeholders)
with keywords; weekly (`memory tidy`), notes on the same app or task with
one changed since are merged (the kept note sums what they proved) and
notes without keywords get some; no call when nothing is to tidy.

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

**Initiative**: the agent speaks first, when something happens it can help
with (`ai.initiative.enable`, off by default). `services/Initiative.qml`
hands events to `nixbook-desktop-mcp initiative consider`: `back` (the
screens on again or unlocked after a while, or the first start of the day:
today's events and tasks, personal-memory events within 3 days or 2 days
past, the usual session when not set up), `focus` (a new app in front, at
most every 3 minutes: a broken recipe of it) with
`ai.initiative.readNotifications`, `notifications` (batched for 45 s), and
`moment` (at random, 40 to 120 minutes apart while active: a light word,
skipped 40% of the time, at most `initiativeChatPerDay`, 3 h apart and 45 min
after anything else, only in the bar: a long stretch, music on repeat, tasks
due after 17h, rain, a tip from a proven note or a macro it has, a plan within
a week, a question on a personal topic unmentioned for 14 days; the model
words only tips and questions, `chat_candidates`/`chat_item`). Plain
code triages (own apps, the focused app's, low urgency, kinds found boring,
silenced apps), checks the value of the kind (replies over words said,
from a prior), dedupes, and delivers: a notification (time-critical; at
most `initiativeMaxPerDay`, `initiativeGapMinutes` apart, none in
`initiativeQuietHours`, in a meeting, fullscreen, on Do Not Disturb) or a
word waiting in the bar (`pending`, the robot's bubble, 6 hours). Spoken out
loud is not a notification: `Initiative.speaking` shows
`modules/ii/notificationPopup/AgentSpeech.qml`, a speech bubble on the left
under the bar, styled per theme (Material, Persona, Chiikawa, Cyberpunk,
Ghibli), to the bar after 25 s unanswered. Only
notifications go to the small model (`INITIATIVE_SYSTEM`, at most
`initiativeCallsPerDay`), which also names kinds never worth a word. The
memory pass offers what it learned (`initiative_offer`). Reply opens the
side panel's "From Claude" tab (`Ai.claudeTab()`, one, reused, past
`maxChats`) with the message as Claude's (`unsent`: it goes with the user's
next message when the tab's session already runs; `GlobalStates.aiChatRequested`);
answers (`initiative answer ID replied|later|dismissed|never`) teach it.
Each decision is logged (`log`, 30 kept; Settings shows the last ones, and
**Say something now** sends a `moment` with `force`: no chance or gap, out
loud, a hello when nothing is on its mind). The small model's Claude Code:
`memoryClaude`, the shell's own (`claude` in the event), PATH, or the usual
install places (`claude_path`). State in `~/.local/state/nixbook-shell/initiative.json`.

**Personal memory**, so a conversation knows what the user told agents
before: life events (past or planned, with dates), plans, people close to
them, preferences, interests. Agents are told to save the meaningful part
of what the user shares (`remember_about_user`: a few condensed facts, not a
transcript), never small talk, one-off requests, desktop how-tos or secrets,
and to do it without asking; `recall_about_user`, `forget_about_user`. It is
kept small and relevant:

- one entry per subject ("japan", "work", "Lan (sister)") of at most 400
  characters, merged as things change: `remember_about_user` on a subject
  that exists is refused until the agent passes the entry's `id` with the
  merged text, and it lists entries on the same subject under another name
  to merge;
- each entry has a kind: `profile` (who the user is: sent in every
  conversation, the agent is told when it grows past 500 characters),
  `person`, `event` (with a `date`: YYYY, YYYY-MM or YYYY-MM-DD) or `topic`;
- when an agent connects it gets, at most `personalPromptChars` (900): the
  profile, events from 14 days ago to 60 days ahead, the subjects talked
  about in the last 14 days and every other subject by name only;
- the entries a message is about come in full with it: the AI chat sends
  them with each message (`nixbook-desktop-mcp personal context`, which
  leaves out those it sent already in the session); other clients that pass
  the task (`NIXBOOK_DESKTOP_MCP_QUERY[_FILE]`) get them in the
  instructions or with the next reply, once.

Agents often don't save mid-task, so the AI chat also runs a **memory
pass**: two minutes after Claude's last answer (or when the chat is cleared
or another loaded), the turns not read yet go to `nixbook-desktop-mcp
personal learn`, which hands them, with the entries they bear on, to a
small model (`ai.claudeCode.memoryModel`, `haiku`) through Claude Code with
no tools, MCP servers or settings, and applies its answer under the same
rules (an existing subject only by id, at most 6 saves and 3 forgets, and
only of entries it was shown); its entries are "by memory pass".
`ai.claudeCode.autoMemory` (on; **Settings → Desktop agents → About you**)
turns it off, and so does the `personal` tool group.

It keeps memories the way a person does, without a token spent in the
conversation (the pass is detached, ~4 s and ~2k tokens of Haiku):

- **importance** 1-5, rated by the pass (agents' own saves: 3; the
  profile: 5);
- **tentative**: what mattered little (1-2) is kept but never sent to a
  conversation (digest, `personal context`; `recall_about_user` still
  finds it) until it comes up again, and is dropped after 60 days;
- **repetition**: the pass lists the entries brought up again with nothing
  new (`recalled`, ids only); each time is a `mention`, ends tentativeness
  and restarts fading, and the 3rd and 6th raise the importance (to 4 at
  most);
- **fading**, in plain Python on each pass: an entry neither updated nor
  used for 90 / 180 / 365 days (importance 1 / 2 / 3) is forgotten; 4-5 and
  the profile never fade; past `personalMaxEntries`, the tentative and least
  important go first;
- **a weekly tidy-up** (`nixbook-desktop-mcp personal tidy` to run it now),
  only when the memory changed and holds 6 entries or more: one call with
  every entry in short (≤ 10k characters) that merges entries on the same
  subject, keeps past events in short, drops what no longer holds and
  re-rates importance; at most 10 changes, and it never forgets the profile
  or an important entry unless merging it into another of its kind.

The personal memory isn't the desktop: its tools work while desktop control
is paused, and the audit log has their ids and kinds only. It lives in
`~/.local/state/nixbook-shell/personal-memory.json` (private), apart from the
desktop memory; **Settings → Desktop agents → About you** shows the entries,
deletes any or all; `nixbook-desktop-mcp personal` shows, forgets, clears or
prints the digest; the `personal` tool group turns it off;
`personalMaxEntries` (200) caps it (the least used go first, never the
profile).

**Usage habits** (off by default; on from **Settings → Desktop agents**,
`nixbook-desktop-mcp habits on|off`: the `habits-enabled` flag the unit's
`ConditionPathExists` checks, and the unit started or stopped; or for good,
the switch locked, with `desktopMcp.habits.enable`): the
`nixbook-habits` user service (`nixbook-desktop-mcp habits watch`) reads
niri's event stream and counts, in plain Python, the focused app's time,
the windows opened, the layouts restored (`layout restore` from the shell)
and the themes chosen (`appearance.theme` in config.json, read every
minute). Desktop ids and times only, never titles (read only to skip
private windows); nothing while locked (`$XDG_RUNTIME_DIR/nixbook-shell-locked`),
paused (`habits-paused`), within 30 s of an agent's action (the state
file's `last`), or for `habitsIgnoreApps` / `habitsIgnoreTitles`; spans
under 5 s are dropped; `habitsKeepDays` (28) kept, in `habits.json` (0600).
For the battery it sleeps until a niri event (60 s at most; a span cut by
the lock or the pause ends at the marker's mtime, not at the wake-up),
appends records to `habits.log` once a minute at most (a long span in
30-minute pieces, merged back on reading), compacts both into `habits.json`
daily, and every 10 minutes (and on the hour) writes `habits-rank.json`
only if it changed (the apps used around this hour, 0-1, and the apps
opened after each app), which `AppSearch.qml` adds to its frecency; then,
at most once a day each: the Monday report notification,
the theme hint (`habitsTheme`), the apps of `habitsOpenAtUsualTime`. A
pattern counts once seen on 3 days. The launcher hands the typed word and
the app opened to `habits alias` (an alias in the desktop memory after two
times, unless the word is in the app's name). Agents get a line in the
memory digest and the `habits` tool (`habitsAgents`: `digest`, `timeline`
for a day hour by hour, `off`). **Settings → Desktop agents → Usage
habits** pauses, shows and clears it.

**Music taste** (part of the usage habits, `habitsMusic`, on with them):
the recorder also follows every MPRIS player (`playerctl --all-players
--follow metadata`, in a thread beside niri's stream: Spotify, YouTube
Music, mpv, KDE Connect…) and records each track as `[start, seconds heard,
player, artist, title, album, length]` (`plays`, `{"m": …}` in the log)
when the player moves on, stops or goes away (`playerctl --list-all` on its
blank line), or after three times its length without an event. Heard 30 s
or half a short track: a play (a repeated track counts each time round);
less: a skip; under 3 s: nothing. No ads or podcast episodes (`/ad/`,
`episode` track ids), no player of `habitsMusicIgnorePlayers` (web
browsers: their tabs' videos); recorded while locked or an agent acts
(the user is still listening), not while paused; `habitsMusicKeepDays`
(365) kept. Artists are split on commas and "feat.", YouTube's "- Topic"
and "VEVO" and title tags ("(Official Audio)") dropped. Agents get the
favourite artists and the last 14 days (new artists marked) in the digest;
`habits` `what=music` adds the top tracks, the artists played around this
hour, the often skipped ones and the players used (`habits music` on the
command line, `habits music-clear` forgets it). Genres aren't recorded:
the model infers them from the artists.

**Window layouts**: `save_layout` remembers where every window is (monitor,
workspace, column and its width, or floating position and size, and the app
that opens it) under a name; `restore_layout` puts them back in one call,
starting the apps that were closed (an app whose first window is a splash,
like Vesktop's "Loading", is placed again once its own window replaces
it: restores that start apps watch them for 5 s). A window already where the
layout has it (monitor, workspace, column and stack, width, floating place) is
left alone, so restoring the layout you're in moves nothing; with two windows of
an app whose titles changed, each goes with the saved place it is in. A maximized
column (Mod+Z) is saved as maximized and maximized again over half the
width, so Mod+Z still unmaximizes it (a column at least 90% of its
monitor's width counts, layouts saved before included). The same layouts are yours in the shell,
where the agents' pause doesn't apply: **Mod+G** opens the launcher as a
layout picker (the `#` prefix: pick one to restore it, update or delete it
with its row's buttons or Shift+Delete, "Save the windows as a new layout",
or type a new name first — spaces become `-`), the desktop's right-click menu has a Window
layouts submenu, and Settings → Window layouts lists them to restore,
update, rename or delete. Key bindings can also call the `layouts` IPC target
(`cycle`, `saveCurrent`, `restoreNumber N`, `restore NAME`, `save NAME`;
agents can't call it), and scripts `nixbook-desktop-mcp layout …`.
They live in `~/.local/state/nixbook-shell/layouts/`. A layout works with
any monitors: it keeps one arrangement per set of monitors it was saved with
(saving off the dock replaces the laptop's and keeps the docked one), and
restoring uses the one for the monitors connected. Without one, the largest
is restored, each workspace of an unplugged monitor on a new workspace of the
focused monitor, columns, widths and floating windows as saved (a named
workspace, which niri keeps, is used as it is). Settings → Window layouts → _Close the other windows when restoring_
(`windowLayouts.closeOthers`, off by default; `layout restore|cycle
--close-others`) makes your restores also close the windows the layout
doesn't have, as their close button would. Never the agents' `restore_layout`.
While one of your restores (or `cycle`) runs, every monitor is dimmed under a
"Restoring the window layout" card that takes the keyboard and pointer, so a
click or key doesn't land on a window being moved; it lifts when the restore
is done (after 30 s at the latest).

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
the pause button and the memory apply as always; tool `none` leaves it out),
the MCP servers of `programs.nixbook-shell.assistant.mcpServers` (by default
[MCP-NixOS](https://mcp-nixos.io), for real NixOS / Home Manager package and
option data; written to `~/.config/nixbook-shell/assistant-mcp.json`, every
tool allowed, left out with tool `none` too) and only the built-in tools in `ai.claudeCode.allowedTools` (web search and
fetch); running commands is refused. **It reads none of
your files** unless you allow it: **Folders AI agents may read**
(`ai.allowedFolders`, none by default) become its `--add-dir` working
directories, read-only, and a file attached to a message is readable alone
(`Read(//that/file)`). Without any, it has no file tools at all
(`--disallowedTools Read Glob Grep`). **Folders AI agents may write**
(`ai.writableFolders`, none by default) are bound read-write into the agent
desktop's sandbox (made if missing; never the whole home or `/`), and the
first is its apps' Downloads folder (`XDG_DOWNLOAD_DIR` in its home), so an
agent can download a file in its own browser and use it on your side, a
wallpaper for instance; Claude can read them and gets `Write` and `Edit`
allowed there only (`Edit(//that/folder/**)`; any other write is denied),
and is told where downloads land. It runs in an empty directory of its own
(`~/.local/share/nixbook-shell/assistant`, not your home) and without your
`~/.claude` settings (`--setting-sources project`: allow rules you set for your
own Claude Code sessions don't apply), and any other read is denied (`-p`
can't ask). Claude Code in a terminal, or any other MCP client, follows its
own permissions.
**Use your claude.ai connectors** (`ai.claudeCode.connectors`, off by
default) also gives it the connectors of your Claude account (Gmail,
Calendar, Drive… as connected on claude.ai, found with `claude mcp list`),
every tool of each allowed without asking; it then drops
`--strict-mcp-config` and keeps their tools behind ToolSearch. A connector
that needs signing in to is signed in to from the panel: Claude gives its
sign-in link, and its tools come once it's done; one signed in to on claude.ai
instead is seen when the panel next opens.
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
  when an agent starts driving the desktop (again after 5 idle minutes;
  `nixbook-desktop-mcp notify off|on|toggle`, the Settings > Desktop agents
  switch or the `desktopControl toggleNotify` IPC call turn it off and on,
  kept across reboots);
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

Several run side by side, one per tab of the side panel's chat working at
once: the tab's desktop MCP server gets `NIXBOOK_AGENT_DESKTOP=N`, and the
Nth desktop is the `nixbook-agent-desktop@N` service ("Assistant's desktop
N", home `agent-home-N`, first copied from `agent-home` without its caches);
the first tab and every other agent use the first. `desktop interact`
takes the one focused, `desktop stop` closes them all (`--instance N`: one).

To you it's one more app window: the agent's desktop shows only the one
app it works in, fullscreen, and kept so even when the app asks to
leave it (Zen and Firefox restore their window size on start; a browser
may hide its tabs and address bar then, so the agents are told to use its
shortcuts): no bar, no focus ring or
borders, no hot corner, and never a layout inside. The agent's other apps
stay open in the background, behind it: `launch_app` leaves them open
(its reply lists them), and `focus_window` brings one back to the front;
the agents are told the desktop can show only one app at a time. The bar widget shows a window icon beside its robot while
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
after a restart. **Closing the window yourself only closes it**: the
agent's next app opens it again, for as long as agents work on their own
desktop; to stop them, switch them back to yours or pause them (the bar's
robot, Mod+Shift+Escape). `desktop user` brings the agents back to
your desktop, `desktop stop` closes theirs, `desktop status` says which is
in use (also `get_status`); the choice survives a reboot. An agent already
at work when you switch is told on its next tool reply ("Desktop switched
by the user: …", with what the desktop it's now on means for it), once per
MCP session, since its instructions only said where it was when it connected.

Its apps are the agent's, not yours, and sandboxed (bubblewrap): **they see
none of your files**. Their home is `~/.local/share/nixbook-shell/agent-home`
(their own browser profiles, history and logins); your GTK/Qt/font settings
are visible read-only so apps look the same, the **Folders AI agents may
read** read-only (from its next start), also where its apps look for them:
a shared folder of your home is at the same place in theirs (their
`~/Pictures` is yours, and is their Pictures folder), and nothing else of your home, of
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
read-only to it, and it watches the session from outside. Log the agent's browser into an account only if you want it to use
that account. File choosers are GTK's own there (the portal's would open on
your desktop).

The shell tools still act on your desktop: `widget` (notes, to-do list,
timers), `tasks`, `calendar`, `notify`, `set_theme` reach your shell over its IPC,
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
| `ghibli`    | `totoro` (default), `spirited`, `mononoke`       | `palette`, `motion`, `shapes`, `fonts`, `spirits`  |

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
the first time: the Chiikawa, Cyberpunk and Ghibli ones; for the lock and login screens, nothing:
they follow the desktop, then the lock screen), and a wallpaper picked while
in a variant becomes that variant's. Settings → Appearance → Theme sets or
unsets all of them at once, in a table of every variant. Each theme has its own sounds too (`sounds` in `themes.json`: the
notification chime and the critical sound — Persona 5's by default, the
Velvet Room's chime and the Evoker in Persona 3 Reload, the Midnight
Channel's TV and the shattering card in Persona 4, the characters' chimes
and little voices in Chiikawa, a message ping and the Relic malfunctioning
in Cyberpunk 2077, the films' sounds recreated in Studio Ghibli); a file set in the settings wins. Important
notifications (critical ones, and those the cut-in rules pick:
Settings → Bar → Notifications → Cut-ins) get the theme's cut-in: the
full-screen Persona one, the Chiikawa character popping up with a speech
bubble (`ChiikawaAlert.qml`), or an incoming holocall glitching in — a
chamfered HUD panel with an RGB split, scanlines and the message typed out
(`CyberpunkCutIn.qml`; `appearance.cyberpunk.glitch = false` keeps it
steady), or a frosted-glass card drifting in on a gust of wind with the film's
spirit leaning on it, among leaves, paper birds or fireflies
(`GhibliCutIn.qml`).

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
(`src/assets/chiikawa/momonga.gif`), the same for every variant; where
there is room (the loading screen, the alert, the wallpapers) it is the three
friends side by side, each its own GIF as is: `chiikawa.gif`, `momonga.gif`
and `usagi.gif` (laid out by `Chiikawa.friendsLayout`); the rest of
its art (the sidebar patterns and the wallpapers, the GIFs' first frames on a
hill) is drawn by `src/assets/chiikawa/generate.py` from the variants'
palettes; rerun it after changing them. Its sounds are synthesized when the package is built
(`src/assets/chiikawa/sounds.py`, no audio file in git): the chimes, with
the characters' own little voices over them (Usagi's "yaha!" and
"pururururu", Chiikawa's "wa!", Momonga's "hya!"), made from scratch.
Every theme's synthesized sounds share `src/assets/synth.py` (a stereo mix
with a room, filters, struck, plucked and blown instruments, formant speech,
effects); they recreate the originals' signature sounds from scratch, with
original tunes. The Cyberpunk 2077
theme works the same way: `src/assets/cyberpunk/generate.py` draws its
wallpapers from the palettes, `sounds.py` synthesizes its sounds at build
time, and its face (Rajdhani) ships in `fonts.nix`.

The Studio Ghibli theme too: `src/assets/ghibli/generate.py` paints the
three wallpapers in a modern illustrated style — volumetric light, bloom,
haze, a colour grade, grain and a vignette — (a summer afternoon with the
camphor tree and the forest spirit; the bathhouse at nightfall over the
flooded plain, the sea train and the masked spirit; the ancient forest full
of kodama), the sidebar patterns
and each variant's spirit (`GhibliSpirit`, in the sidebars' corner, on the
loading screen and on the cut-in), and its faces (Zen Maru Gothic, Klee One
for titles) ship in `fonts.nix`. `src/assets/ghibli/sounds.py` recreates the
films' signature sounds from scratch at build time, fitted to what each one
announces — raindrops on an umbrella, the forest spirit's roar, a wind chime,
an ocarina (Totoro); a rin bowl, the bathhouse drum and bell, the sea train's
crossing bell, paper birds, a piano waltz (Spirited Away); the kodama's
rattle, the wolf's howl, the forest spirit's step, a shakuhachi over a taiko
(Mononoke) — produced like a modern film score (felt piano, string pads, a
soft sub, risers into the big hits, a warm tape master). No sample or melody is taken from the films: the tunes are
original, only the instruments and the idiom are borrowed.

Settings that did nothing were removed (`lib.nix` `removedKeys`: the parallax
options, `bar.topLeftIcon`, the settings window border…); an old Nix
configuration setting one still evaluates, with a warning, and the value is
ignored.

## Layout

| Path               | What                                                                                                                         |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------- |
| `default.nix`      | entry point (`package`, `homeManagerModules.default`, `lib`)                                                                 |
| `package.nix`      | the launcher: runtime `PATH`, QML import path, `config` CLI                                                                  |
| `accounts.nix`     | `nixbook-accounts` (`accounts/`, Go): the accounts (Google, CalDAV/CardDAV), contacts, tasks, calendars                      |
| `qml.nix`          | the QML tree as installed (store-path fixups, Persona, Chiikawa, Cyberpunk and Ghibli art and sounds, emoji list)            |
| `fonts.nix`        | the faces `appearance.fonts` names that nixpkgs lacks (Google Sans Flex, Space Grotesk, Rajdhani, Zen Maru Gothic, Klee One) |
| `quickshell.nix`   | Quickshell from `quickshellSrc` plus `patches/`                                                                              |
| `lib.nix`          | typed settings options generated from `builtin-defaults.json`                                                                |
| `hm-module.nix`    | the Home Manager module `programs.nixbook-shell`                                                                             |
| `nixos-module.nix` | optional NixOS module: the system's toggles for the assistant                                                                |
| `greeter.nix`      | the login screen (`nixbook-shell.greeter`, imported by it)                                                                   |
| `toggles.nix`      | discovers the `enable` toggles from an options tree                                                                          |
| `scripts/`         | `config` CLI, its jq library, assistant facts, Anthropic usage, login screen theme, emoji list, desktop control MCP server   |
| `npins/`           | default nixpkgs and quickshell pins                                                                                          |
| `src/`             | the QML tree                                                                                                                 |
| `tests/`           | script tests, lib unit tests, the self-containment check                                                                     |

## Tests

```sh
bash tests/scripts.sh
bash tests/desktop-mcp.sh    # the desktop control MCP server, against stub niri/wtype/grim… and a fake compositor
nix-instantiate --eval --strict --json --expr 'import ./tests/lib.nix { }'   # []
nix-instantiate --eval --strict --read-write-mode tests/standalone.nix \
  --arg homeManager '<home-manager checkout>'                                  # "ok"
```
