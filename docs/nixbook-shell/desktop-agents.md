# Desktop control for AI agents

`nixbook-desktop-mcp` (also `nixbook-shell mcp`) is a [Model Context Protocol](https://modelcontextprotocol.io) server that lets an AI agent **see and drive the desktop**. Any MCP-capable agent can use it — Claude Code, OpenCode, Codex, and the shell's own [Claude panel](./ai-assistant#claude-in-the-side-panel).

```bash
claude mcp add desktop -- nixbook-desktop-mcp     # Claude Code
# OpenCode, Codex…: a local (stdio) server running `nixbook-desktop-mcp`
```

::: warning Starts paused
Desktop control **starts paused**. Allow it with the bar's Desktop Control widget, **Mod+Shift+Escape**, or `nixbook-desktop-mcp resume`. The choice survives reboots; a fresh install stays paused until you allow it.
:::

## What agents can do

| Group      | Tools                                                                                                                                                                                                                                                     |
| ---------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `observe`  | List windows, workspaces and apps; **the machine itself**, read live: OS, kernel, CPU, memory, GPUs, displays, disks, temperatures, battery, network (`system_info`, also while paused)                                                                   |
| `screen`   | Silent screenshots (a monitor, a zoomed-in region, a window); **OCR** of the screen with positions to click (~150 tokens instead of ~1,250 for a screenshot); the clipboard; recent notifications as text; save screenshots and record the screen for you |
| `windows`  | Focus, move, resize, close windows; launch apps (waits for the window); [window layouts](./window-layouts)                                                                                                                                                |
| `input`    | Type, press keys, click, drag, scroll — exact to the pixel on any monitor and scale; up to 20 steps in one call (`run_steps`)                                                                                                                             |
| `ui`       | Read any app's window through its **accessibility tree** (buttons, fields, labels as numbered text lines) and press, toggle or fill elements without coordinates; wait for an element to appear or disappear                                              |
| `shell`    | Themes and variants, the wallpaper, **desktop widgets** (notes, to-do, timers, alarms, images, music recognition), the **equalizer**, the **calendar** (read-only), notifications, shell panels                                                           |
| `memory`   | [Desktop memory](#desktop-memory): remember, recall, forget                                                                                                                                                                                               |
| `personal` | [Personal memory](#personal-memory): what you told agents about your life                                                                                                                                                                                 |

Agents are told to read through OCR or the accessibility tree before taking a screenshot, and screenshots are JPEG and **incremental** — only what changed since the agent's last one — to keep each call cheap. Action tools can return a screenshot of the result in the same call, once the screen stops changing.

## Guardrails

Whatever the transport:

- **No tool runs a command**: apps start from their `.desktop` entry only (no arguments, no terminal apps); Niri actions and shell IPC calls are a fixed, validated set; the `session`, `nixManaged`, `desktopControl` and `layouts` IPC targets are off limits.
- **No keyboard or pointer input into terminals, password managers or password prompts** (`inputDenyApps`, `inputDenyTitles`); no Super combinations (compositor bindings), Ctrl+Alt+Delete or Ctrl+Alt+F-keys. Password fields never show their text through the accessibility tools.
- **A pause button** for every agent at once (the bar widget, Mod+Shift+Escape, `nixbook-desktop-mcp pause`) — it even stops between the steps of a batch.
- **Rate limits**: 120 actions a minute, 4,000 characters per typed text.
- **A notification** when an agent starts driving the desktop (again after 5 idle minutes; can be turned off).
- **An audit log** of every call in `~/.local/state/nixbook-shell/desktop-mcp.log` (typed and copied text by length only).

For agents to work without touching your windows at all, give them [their own desktop](./agent-desktop).

## The Desktop Control widget

The `desktopControl` bar widget shows a **faint robot** when idle, a **pulsing robot** while an agent acts, and a **red hand** when paused; its tooltip names the last agent and tool. Click pauses or allows every agent; right-click switches the agents to [their own desktop](./agent-desktop). Settings → Desktop agents has the same switches, the memory, and the Claude panel setup.

## Desktop memory

So the next task is faster, agents keep **notes** about your desktop — an app's shortcut, where a setting is, which app does what — and **recipes** (`run_steps` saved with `remember_as`). Usage is counted as they work, and `launch_app` learns **aliases** ("discord" → Vesktop).

Only the relevant part reaches a model: when an agent connects it gets a short digest (aliases, most-used apps, the notes about the task in full, the other notes by topic only); notes about an app also arrive with the action that opens it. With 40 notes, the digest is about 165 tokens. Notes are labelled as hints written by agents, never your instructions.

- **Settings → Desktop agents** shows the notes (delete any), aliases and usage, and clears them.
- `nixbook-desktop-mcp memory show|prompt|forget ID|clear`.
- Stored in `~/.local/state/nixbook-shell/desktop-memory.json` (private).

## Personal memory

Tell Claude in the side panel (or any agent) about your life — a trip you're planning, someone close to you, an event coming up — and later conversations know it. Agents keep **the meaningful part**, without asking: a few condensed facts, never a transcript, small talk, one-off requests or secrets. Ask them to remember or forget something, or what they know about you.

It is organised so it costs few tokens:

- **one entry per subject** ("japan", "work", "Lan (sister)"), at most 400 characters, merged as things change (agents must update the existing entry rather than add another);
- each entry is your **profile** (who you are: sent in every conversation, so kept short), a **person**, an **event** (with a date) or a **topic**;
- a conversation starts with your profile, the events coming up or just past, and the other subjects **by name only** (about 900 characters at most);
- when you talk about a subject, its entry comes with your message: say "I booked the flight to Kyoto" and the "japan" entry is there, so Claude can update it.

Claude doesn't always stop to save mid-task, so the side panel also runs a **memory pass**: a couple of minutes after the last answer (or when you clear the chat or load another), a small model (`ai.claudeCode.memoryModel`, Haiku by default) reads the new turns and saves or updates what is worth keeping, by the same rules. Turn it off with **Remember on their own** in **About you** (`ai.claudeCode.autoMemory`).

It remembers the way a person does:

- each memory has an **importance** (1-5): who you are and the people closest to you never fade; big plans and events matter more than passing interests;
- a **passing mention** ("I might try pottery") is kept only tentatively: never brought into a conversation, and forgotten after two months unless it comes up again;
- what **comes up again** is held more firmly: it stops being tentative, and the third and sixth time it becomes more important;
- what is **never used fades**: after 3, 6 or 12 months for importance 1, 2 or 3;
- once a week it **tidies up**: merges memories about the same subject, shortens past events, drops what no longer holds.

All of it runs in the background after the chat, with a small model (about 4 s and a fraction of a cent a pass): your conversation is no slower and carries no more tokens — tentative memories even keep it smaller. **About you** shows each entry's importance and whether it is tentative.

- **Settings → Desktop agents → About you** shows the entries (delete any, or all).
- `nixbook-desktop-mcp personal show|prompt|learn|forget ID|clear`.
- Stored in `~/.local/state/nixbook-shell/personal-memory.json` (private), apart from the desktop memory. Its tools work while desktop control is paused (they don't touch the desktop), and the audit log never has their text.

## HTTP transport

Over stdio nothing listens anywhere. For an agent that can only reach a URL, `programs.nixbook-shell.desktopMcp.http.enable` runs the server at `http://127.0.0.1:7823/mcp`:

- bound to **loopback only** (no port is opened to the network);
- a **bearer token** (`Authorization: Bearer $(nixbook-desktop-mcp token)`), kept in a 0600 file in the runtime directory;
- the connecting process must belong to **the same user**;
- Host and Origin headers must be loopback (no DNS rebinding from a web page).

## Configuration

```nix
programs.nixbook-shell.desktopMcp.settings = {
  tools = [ "observe" "screen" "windows" "ui" ];  # tool groups (default: all)
  actionsPerMinute = 60;
  inputDenyApps = [ "^org\\.keepassxc\\.KeePassXC$" ];
  ocrLanguages = [ "eng" "fra" ];
};
```

Written to `~/.config/nixbook-shell/desktop-mcp.json`; `nixbook-desktop-mcp config` prints what applies. Other keys tune screenshots (`screenshotFormat`, `screenshotQuality`, `screenshotMaxEdge`) and memory (`memoryPromptChars`, `memoryMaxNotes`, `personalPromptChars`, `personalMaxEntries`).

The `ui` group needs the accessibility bus (`customNixOSModules.niri.accessibility`, on by default); the module sets the variables that make Firefox-based and Chromium/Electron apps publish their tree (apps started before need a restart).
