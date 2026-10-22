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

| Group      | Tools                                                                                                                                                                                                                                                                                           |
| ---------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `observe`  | List windows, workspaces and apps; **the machine itself**, read live: OS, kernel, CPU, memory, GPUs, displays, disks, temperatures, battery, network (`system_info`, also while paused)                                                                                                         |
| `screen`   | Silent screenshots (a monitor, a zoomed-in region, a window); **OCR** of the screen with positions to click (~150 tokens instead of ~1,250 for a screenshot); the clipboard; recent notifications as text; save screenshots and record the screen for you                                       |
| `windows`  | Focus, move, resize, close windows; launch apps (waits for the window); [window layouts](./window-layouts)                                                                                                                                                                                      |
| `input`    | Type, press keys, click, drag, scroll — exact to the pixel on any monitor and scale; up to 20 steps in one call (`run_steps`), a saved recipe in one call (`run_recipe`)                                                                                                                        |
| `ui`       | Read any app's window through its **accessibility tree** (buttons, fields, labels as numbered text lines) and press, toggle or fill elements without coordinates; wait for an element to appear or disappear                                                                                    |
| `shell`    | Themes and variants, the wallpaper, **desktop widgets** (notes, to-do, timers, alarms, images, music recognition), the **equalizer**, the **calendar** (read-only), the **to-do lists**, **[contacts](./accounts)** (every account's: search, edit, label, photos), notifications, shell panels |
| `memory`   | [Desktop memory](#desktop-memory): remember, recall, forget; remind (reminders on a cue); [routine](#routines)                                                                                                                                                                                  |
| `personal` | [Personal memory](#personal-memory): what you told agents about your life                                                                                                                                                                                                                       |

The `memory` group also has `habits`: what you usually do, from [usage habits](#usage-habits) when you turned them on.

Agents are told to read through OCR or the accessibility tree before taking a screenshot, and screenshots are JPEG and **incremental** — only what changed since the agent's last one — to keep each call cheap. Action tools can return a screenshot of the result in the same call, once the screen stops changing.
**The shell gets out of the way.** When the side panel, Claude's speech bubble, notification popups or a theme's cut-in are over the apps while an agent works on your desktop, they become click-through, let go of the keyboard and are hidden from its screenshots for that instant. You still see them, slightly faded, with _Claude is working under this panel_ on the side panel, so you can follow the chat while it works underneath. This lasts only while each of its actions or screenshots goes on, and 1.5 s after: between its steps, while it thinks, you can use them again, exactly as they were; nothing is dismissed or put away. The agent is told what was on screen and can hide popups, a cut-in or the bubble while it works with `set_aside` (they come back the same way), but never the side panel, the lock screen or a password prompt. When nothing of the shell is on screen this costs nothing: it is one small file read per action.

## Guardrails

Whatever the transport:

- **No tool runs a command**: apps start from their `.desktop` entry only (no arguments, no terminal apps); Niri actions and shell IPC calls are a fixed, validated set; the `session`, `nixManaged`, `desktopControl` and `layouts` IPC targets are off limits.
- **No keyboard or pointer input into terminals, password managers or password prompts** (`inputDenyApps`, `inputDenyTitles`); no Super combinations (compositor bindings), Ctrl+Alt+Delete or Ctrl+Alt+F-keys. Password fields never show their text through the accessibility tools.
- **A pause button** for every agent at once (the bar widget, Mod+Shift+Escape, `nixbook-desktop-mcp pause`) — it even stops between the steps of a batch.
- **Rate limits**: 120 actions a minute, 4,000 characters per typed text.
- **A notification** when an agent starts driving the desktop (again after 5 idle minutes; can be turned off).
- **An audit log** of every call in `~/.local/state/nixbook-shell/desktop-mcp.log` (typed and copied text by length only).
- **What it sent**: everything given to a small model (notifications, pairing, news, memory passes…) and the context sent with a question asked in the bubble, as sent, the last 7 days: Settings → Desktop agents → **What it sent** (`nixbook-desktop-mcp sent`, `~/.local/state/nixbook-shell/sent.jsonl`, readable by you only; **Forget it** empties it). A local model's are marked: they never left the computer.

For agents to work without touching your windows at all, give them [their own desktop](./agent-desktop).

## The Desktop Control widget

The `desktopControl` bar widget has a button for each thing it does, each with its own tooltip saying what a click does:

- **Claude** (a robot): ask Claude anything in its bubble, again to put it away (Mod+C). It hops when Claude has something new to say.
- **Something for you** (a speech bubble, only then): click to read it in Claude's bubble, right-click for not now.
- **Desktop control**: a **pause** button while agents may act (faint when idle, pulsing while one acts; its tooltip names the last agent and tool), a **red play** button while paused. Click pauses or allows every agent.
- **Where agents work** (a monitor, or a window icon while they're on [their own desktop](./agent-desktop)): click switches.
- **Fixing nixbook** (a wrench, only while it works): click to see it in Settings. Settings → Desktop agents has the same switches, the memory, and the Claude panel setup.

## Turning AI off

**Settings → Desktop agents → AI features** (also Settings → Panels → AI: _No_, _Yes_, _Local_; `policies.ai`: 0, 1, 2) switches all of it at once:

- **Off** (`0`): nothing calls a model, and no agent acts:
  - no chat in the side panel, and Claude never speaks on its own (Mod+C included);
  - no routine runs, no memory pass, no fix (nixbook-improve), and the equalizer agent rests;
  - every agent's desktop tools are refused, Claude Code in a terminal included.

  What agents remember stays, unused, and each feature's own switch keeps its position for when you turn AI back on.

- **Local** (`2`): nothing goes to an online model like Claude: no Claude chat, memory pass, fix or equalizer agent. Local agents keep the desktop tools, and routines with a fixed action still run. With **Talk to me on its own** on, what is plain code keeps working (the brief, reactions' **Open** and **Show in folder**, routines' reports, watches, focus holding), without anything to answer Claude in. Pairing and reading notifications can use a model running on this computer: an OpenAI-compatible server on the loopback (Ollama, llama.cpp, LM Studio), set in `desktop-mcp.json` as `"localModel": {"url": "http://127.0.0.1:11434/v1", "model": "qwen2.5:7b"}` (never another host; no web search, so no links).

## Talks to you on its own

Turn on **Settings → Desktop agents → Talk to me on its own** (off by default) and Claude speaks first when it can help. There is no schedule: it reacts to what happens.

- **When you come back** (the screens come on, you unlock, the first start of the day): a word on your day. It covers today's events and tasks due, a plan from [what it remembers about you](#personal-memory) coming up ("Kyoto trip: in 2 days. Want help getting ready?") or just past ("how did it go?"), and your [usual start](#usage-habits) when it isn't set up, with a **Set it up** button that restores the layout and opens the apps at once (no Claude run). The same goes for every offer whose follow-up needs no thinking: tasks still due in the evening (**Move to tomorrow**, **Show them**), a recipe it learned (**Show it**, **Forget it**), a watched unit that failed (**Show the log**).
- **When an app is in front** that has a recipe it knows is broken: it offers to fix it.
- **When it learned something** (a recipe from a task): it tells you, and you can see it or have it forget it.
- **Notifications**, with **Read my notifications** also on: it reacts to what comes in, of any kind, with advice or a suggestion. For example: a low battery before a meeting, a full disk, a failed build or backup, a delivery, a bank or security alert, a message that asks something.

- **Now and then, a light word**, the way someone in the room would. At random moments (every 20 minutes to an hour while you are at the computer), it may say something, and most of the time it doesn't. What it can say:
  - from what is happening: you have worked for 2 hours straight, you have had an artist on repeat today, tasks are still due late in the day, it's raining outside;
  - from what it knows that may help you: a tip for the app in front (from a note of its own that proved itself), something it can now do in one step (a macro), a plan of yours a few days away, a casual question on something you care about that hasn't come up in a while.

  At most 4 a day (`initiativeChatPerDay`), 75 minutes apart, never soon after anything else, and only as the bubble in the bar, never a notification. A small model words only the tips (and drops notes that are only for agents, never asking about them again) and the casual questions; the rest is plain code.

- **Curious**, with **Be curious** also on (off by default): it watches what you do and learns it by itself. Every few minutes while you are at the computer it notes the app and window title in front (never password managers or private windows, `habitsIgnoreApps`/`habitsIgnoreTitles`; kept 7 days). Every few hours (5 at most), when it saw enough new things, a small model reads those titles with what it already [knows about you](#personal-memory), saves the lasting facts there (a project you work on, an interest, a plan), and Claude tells you in its bubble: "I've been looking at what you do, and noticed: … tell me if I got it wrong." Reply to correct or complete it. It asks a question only when something that matters is unclear. And when what you have in front looks like something it can help with (a long page or thread, a message to answer, an error, something to find or compare), it offers: "You've had that thread open a while: want me to summarize it?". Reply, and Claude does it. It needs to ask less as it knows more: what the memory has is no news, and titles it read aren't sent again. Window titles go to the small model, every few hours at most.
- **News**, with **Tell me the news I'd care about** also on (off by default): about once a day, outside quiet hours and never while you're busy, a small model searches the web for what's new on the subjects you talk about with Claude most (the topics of what it [knows about you](#personal-memory), never people or events). Claude then sums it up in its bubble: what's happening in a sentence or two, then up to 4 items, the most interesting for you first. Each has its link as a button under the bubble, and the thread in the side panel has the links and a line on each. Reply to hear more about one. A link it told you is never told again; **Don't tell me this** stops the news. It also tells you what's happening where you are (the weather's city and country, or `newsLocation` in `desktop-mcp.json`). Add subjects of your own with `initiativeNewsTopics` (a list) in `desktop-mcp.json`. A link opens in your browser and brings it to the front. **Find news now** in Settings runs it at once. Only the subjects go to the search.
- **Pairing**, with **Pair with me** also on (off by default): while you stay on something, every couple of minutes it looks at what you're on (the app and the window title; with **read the screen's text too**, also what's on screen, read on this computer). It guesses what you're doing and speaks only when it truly helps: an error and its fix, a better way, a shortcut you seem to miss, the page that answers it. It searches the web first when that helps, with generic queries, never your data. It never gets in the way: the word comes as a small bubble only once you pause (a few seconds without input), at most one look every 5 minutes, quiet for 20 minutes after a word, 30 looks a day (`pairCallsPerDay`). Privacy: never chats, mail, banking, password managers or private windows (`pairIgnoreApps`, `pairIgnoreTitles`); the screen isn't read while one of them is on the workspace; secrets, passwords, keys, card numbers, e-mail addresses and phone numbers are removed before the small model sees anything; nothing it read is kept. **Not now** and **Don't tell me this** teach it, like every word. While it reads the screen, an **eye** shows in the bar (click it to stop reading the screen).
- **What you were just doing**, with **Know what I was just doing** on (off by default): the shell keeps the last 15 minutes in memory (never on disk): the windows in front and their titles, a command that failed in a terminal, an error you copied. When you ask something in the bubble (Mod+C), that goes with your first message, so you don't have to explain: the bubble says **Knows what you were just doing** (hover it to see exactly what; × leaves it out). Private apps and windows are left out as for pairing, secrets and numbers removed, 15 lines at most. Back from a break of 10 minutes or more, a quiet word says where you were ("Before the break you were on kitty: nix build, and a command was failing…").
- **A command that keeps failing**, with **Help when a terminal command keeps failing** on (off by default): the same command failing twice in 10 minutes (zsh or bash) offers **Explain it**. The shell hook writes only the command, its folder and exit code, only while the switch is on, never the output, never Ctrl+C or a command starting with a space. Nothing goes to Claude until you click.
- **An error you copy**, with **Help with an error I copy** on (off by default): copying an error or a stack trace offers **Explain it** (never what a password manager copied). Nothing goes to Claude until you click.
- **Watches**: ask Claude "tell me when the build is done", "ping me when CI passes", "let me know when the site is back" and it watches in plain code, no token: a process, a systemd unit, a download done growing, a GitHub Actions run or a pull request's checks (your `gh`, read only), a web page answering again. When it's done, it says so in its bubble (a notification while **Talk to me on its own** is off), even past the day's budget and at night. Settings lists them with **Stop**; they end after 12 hours.
- **Focus**, with **Don't interrupt me while I'm focused** (on by default): after 10 minutes at something (one or two apps, no minute away), quiet words wait, and come together at the next break (a third app, or a minute away). Urgent ones (a watch, a reaction, something critical) still come.

How it reaches you:

- **Its own speech bubble**, for what is time-critical: not a notification but Claude itself, on the left under the bar (your notifications stay where they are), in the theme's look: a Material card, a slanted Persona frame, a round pastel Chiikawa bubble, a notched neon Cyberpunk panel or a paper Ghibli card. It is a small chat: type your answer in it (Enter sends, Shift+Enter for a new line, Escape puts it away; the new-chat button, or typing `/new` or `/clear`, starts a new conversation, the one before staying in the side panel's history) or pick a quick answer (**Yes, please** / **No thanks** under a question, **Not now**, **Don't tell me this**), and Claude answers right there, saying what it is doing meanwhile (thinking, the tool it used). Left alone (25 seconds before you answer, 90 seconds after its answer; it waits while you hover it or type), it moves to the bar with the conversation; Claude's next answer brings it back. Its other words pile up as small bubbles under it (3 at most, the oldest going to the bar), like notifications: what it says while the bubble is taken, a word that left unread, and its quiet words (pairing, what it learned, a routine's report), which slide in only once you pause. Click one to open it in the bubble (a conversation there goes to the bar, and comes back from it or with Mod+C: only the conversation does), or use its button right there (Yes, a link, Reply). One that waits for your answer (a question, a Yes, buttons) stays until it expires; the others go to the bar a minute after you read them, or after 10 minutes. Its × is **Not now**. At most 8 a day, 20 minutes apart, and none at night (22:00–8:00), in a meeting, fullscreen or on Do Not Disturb.
- **The expand button** moves the conversation to the side panel, on its own **From Claude** tab, always the same one (made when missing, even with every tab in use). Claude knows what it said, even when that tab already has a conversation going. Left alone for 30 minutes (`ai.claudeThreadIdleMinutes`, Settings > Services; 0 keeps it), the tab closes and its thread stays in the conversation history, marked **From Claude**, when it has more than 5 messages (shorter ones aren't kept).
- **Ask it anything**: **Mod+C**, or a click on the robot in the bar, opens the bubble to type in; pressing it again puts the bubble away. A plain command is done at once, without Claude (which can think for a while), and the bubble says what it did: **open** an app (when its name is certain), **play**, **pause**, **next**, **previous**, **volume 40** / **volume up** / **mute**, **brightness up**, **dark mode** / **light mode**, **do not disturb on**, **lock**, **timer 10 min**, **pomodoro**, **work layout** (a saved layout), **task: buy milk**, **settings**. Anything else, or anything unsure, goes to Claude as before. A new conversation started there is a normal one, in the side panel's tabs and history like any other, not a **From Claude** thread. A chat of the side panel that answers while the panel is closed also says so in the bubble, its answer there to reply to.
- **Reactions**, with **React to what I do** on (off by default): when you download a file, take a screenshot or plug in a drive, the bubble offers one-click help: **Open**, **Show in folder**, and by the file's kind **Summarize it**, **What's in it?** or **How do I install it?** (those ask Claude, the file attached), or **Extract it** (done at once, into a folder next to it, then shown). Plain code, no model call until you click; not for what an agent did, never while you are busy, once per file, gone after 15 seconds (30 minutes in the bar); **Don't tell me this** silences that kind only.
- **A bubble button beside the robot in the bar** for the rest, breathing slowly. Click it to bring it (or your conversation) back in the speech bubble, right-click for not now. The robot hops when Claude has something new to say and nods while it answers. These expire after a few hours.

It costs little and learns what you value:

- **Plain code decides** whether a word is worth it: is it new, are you free, is the day's budget spent, do you usually take up this kind (and this app's notifications). No model runs for that.
- **A small model** (`memoryModel`, Haiku) only reads notifications, in batches of up to 6, after the triage has dropped its own, the focused app's (you see them), low-urgency ones and kinds it found not worth a word before (those are never sent again). There are at most 30 calls a day (`initiativeCallsPerDay`). Everything else is worded in code.
- **It adapts to you:** the day's budget follows your answers, up to twice the base when you take up most of what it says and down to half when you ignore it (`initiativeChatPerDay` too). It speaks out loud less at times of day you rarely answer. A reply that turns into a conversation counts more than a one-word one. It learns which apps' notifications you act on and which you dismiss unread: the latter stop being read at all. Something urgent still gets through a spent budget, unless you are busy.
- **Your answers teach it:** a reply makes that kind more likely, a dismissal less, and **Don't tell me this** silences that kind (or that app's notifications, or that routine's reports). Settings has a button to undo every "don't".

**Say something now** (Settings) makes it speak at once, to try it; a test spends none of the day's budget and holds nothing back. While it (or **Find news now**) runs, the button says so with a bar moving under it; then a line tells what came of it: said in the bubble, waiting in the bar, or nothing worth saying. When the next light word is due, and how long you have been at the computer, are kept across shell restarts (every switch restarts the shell). Under it, **Lately** lists its last decisions: what it said, or why it kept quiet ("nothing to say", "said one lately", "the user is busy"…).

Keys in `desktop-mcp.json` (`programs.nixbook-shell.desktopMcp.settings`): `initiativeMaxPerDay` (8), `initiativeGapMinutes` (20), `initiativeQuietHours` (`"22-8"`), `initiativeCallsPerDay` (30), `initiativeChatPerDay` (4), `initiativeNewsTopics` (`[]`), `newsModel` (the memory model), `pairCallsPerDay` (30), `pairIgnoreApps`, `pairIgnoreTitles`. The switches are `ai.initiative.enable`, `ai.initiative.readNotifications`, `ai.initiative.curious`, `ai.initiative.reactions`, `ai.initiative.news`, `ai.initiative.pair` and `ai.initiative.pairReadScreen` in the shell's settings. State lives in `~/.local/state/nixbook-shell/initiative.json` (private); `nixbook-desktop-mcp initiative show|pending|news|unmute|clear`.

## Routines

Ask Claude for something to happen on its own whenever something happens on the computer: "whenever the music ends, play something I like", "when my headphones connect, resume the music", "when a PDF lands in Downloads, open it", "every weekday at 9:00, restore my work layout".

- **Cues**, watched by the shell in plain code:
  - music: ended on its own, started, a new track, **on repeat** (`music_repeating`: the same song `times` times in a row, 3 by default, a loop on repeat-one included, or the same artist for `minutes`, 30 by default; seen by the shell, so no Claude run until it happens), and **no music for a while** (`music_silent`, `minutes`: "whenever there's no music", also when you sit down to silence; held while you stopped it yourself, until you play something or come back from a break);
  - apps: opened, closed, **in front** (`app_focused`), words in a window title, a notification;
  - you: the **first time at the computer today** (`day_start`, once a day), coming back, leaving (`away`), **a long sitting** (`long_session`, 90 minutes), the screen locking or unlocking;
  - modes: fullscreen on or off, Do Not Disturb on or off;
  - devices: the battery low or **charged** (`percent`), the power cable, Bluetooth devices, **your phone** through KDE Connect, a **USB drive**, the audio output, a monitor;
  - the rest: a time (and days), Wi-Fi, the VPN, a file arriving in Downloads, a **screenshot**, a calendar event starting, the **system disk** filling up (`disk_low`), **rain** in the weather.
- **Actions:** a fixed tool call that costs nothing each time: a desktop tool among those that can't type, click, read the screen or the clipboard (open, focus, move or close windows, restore a layout, a theme, the wallpaper, the equalizer, a widget, a notification, and the music through `mpris`), or a tool of the side panel's MCP servers (YouTube Music, Spotify…; those you turned off for the side panel are off here too). It can also be a few such calls in a row (up to 5), and it runs at once. `{liked}` in a call's arguments is a song you like ("Title Artist"), picked in plain code from your [listening history](#usage-habits). So "whenever there's no music, play something I like" or "change the song on repeat" is a fixed action too: play `{liked}`, then queue another `{liked}`. Each pick is by another artist, weighted to what you play most, around this hour and lately. It is never a track heard in the last 3 hours, an artist you often skip, or the artist on repeat. The arguments can also hold what just happened, filled in plain code: `{file}` (the download, screenshot or drive), `{app}`, `{name}` (the Wi-Fi network, Bluetooth or audio device, monitor, phone or file name), `{time}` and `{date}`. They never hold a text someone else wrote, such as a notification's or a window title's. A routine can use one only with an event that tells it. **open_file**, a routine's own action, opens `{file}` with its default app, so "when a PDF lands in Downloads, open it" runs at once. It only opens what's in your home or on a drive, and never a program (a script, a `.desktop` file, anything executable). When the action takes judgment beyond that ("something I'd like for this time of day"), it is a short Claude run instead, with only the servers it names and a desktop without input, screen, memory or personal tools (`observe`, `windows`, `shell`), never told the text of what happened (only the app, a name, the words that matched…), and never while the screen is locked; at most `routineAgentPerDay` (20) a day, on `routineModel` (Haiku).
- **You say yes first.** A routine Claude adds (or asks to turn on) stays off until you answer **Yes, do it** to its bubble, which says what it would do ("Shall I add this routine? … when music ends, youtube-music: play …"). Clicking its bubble in the bar brings that speech bubble back; **Not now** leaves the routine off (the Settings switch can still turn it on), **Don't tell me this** deletes it. The switch in Settings and `nixbook-desktop-mcp routine on` turn one on directly.
- **It never fights you.** Music routines fire only on music that ended on its own (the track played to its end, the queue ran out) and stayed quiet for 20 seconds, never after you paused or stopped it; music you stop holds music routines for 10 minutes. Each routine waits its `cooldown` (10 minutes) between runs. Undo what a routine just did twice in a day (pause the music it started, close the app it opened, within 3 minutes) and it turns itself off and tells you. A run that changed nothing can't be undone, and a pause while a routine runs (switching tracks) isn't counted as yours. The pause of desktop control stops routines too.
- What a routine did comes as a word in the bar. One that fails says so too (once a day), with why.
- **Seen lately** under the routines lists what the shell saw and what came of it ("music: ended on its own, waiting 45 s", "paused by you (holding music routines 10 min)", "ran", "failed: …"), so you can see why a routine ran or didn't.

**Ideas.** With **Talk to me on its own** on, once a day it looks at what it knows about you (your memory entries, habits, music taste, the devices and networks you use) and your routines, and may suggest one that would help ("You back up photos most evenings. Shall I add this routine? When my backup drive is plugged in, open it in Dolphin"). It is added off and turned on only by your **Yes, do it**; one you turn down isn't suggested again. People go in by name and relation only, never their address, phone or e-mail. `nixbook-desktop-mcp initiative ideas` asks for one now.

**Learned on their own.** With **Learn routines from my habits** (Settings, `ai.routines.learn`: off by default), it reads your [usage habits](#usage-habits) once a day (they need to be on). It looks for what you do by hand after the same cue, or at the same time of day: opening an app, restoring a layout, switching theme, putting music back on. Cues include headphones or another audio output, Wi-Fi, a monitor, the power cable, unlocking, or opening another app. A pattern needs at least 3 days, and 3 times out of 5. _Suggest_ asks first ("I noticed you open Firefox when your headphones connect (5 of 5 days). Want me to do it for you?", with **Yes, do it**). _On its own_ turns a strong pattern on at once (5 days, 4 times out of 5, or 7 days for a time of day) and tells you each time it acts, until it has done it 3 times without you undoing it. A learned routine is always a fixed action, so it never costs a token. One new pattern a day at most, and one you decline is never offered again. To learn from them, the habits also count the cues the shell sees (device and network names only).

**Settings → Desktop agents → Routines** lists them (on/off, delete, last result) and has the **Run my routines** switch (`ai.routines.enable`). `nixbook-desktop-mcp routine list|run ID|on ID|off ID|remove ID`.

## Fixes it makes itself

On machines that have it (totoro), tell an agent something of nixbook is broken ("report this") and, with **Fixes it makes itself** on, its `report_problem` tool files it for the fixer. The fixer makes a small fix in a confined Claude Code session, checks it and opens a pull request you merge. See [Fixes it makes itself](./self-improve).

## What agents can't do

Whatever an agent is told (a page or a message can try to steer it), the desktop tools refuse:

- **Typing or clicking into** a terminal, a password manager or a password prompt, the shell's own Settings window (an agent could loosen its own rules there), a terminal inside an app (Dolphin's F4 panel, an editor's, found by its accessibility role; when it can't be checked, typing into those apps is refused), the keys that open one, and a browser's developer tools (F12, Ctrl+Shift+I/J/K/C…). Accessibility actions (`ui_act`) refuse password fields and terminals too.
- **Running a command through the shell**: every key or click from an agent is stamped first, and for 3 seconds after one the launcher won't run a `$` command and the side panel won't send a message to Claude (a notification says so; if it was you, do it again).
- **Reading a password** the clipboard holds from a password manager (marked by it), or keeping one after pasting.
- **Planting instructions in memory**: no note or personal entry can tell agents to ignore their rules or to send something somewhere, whatever source it claims; notes read in content or inferred stay tentative and aren't given to agents unasked until they prove useful.
- **Notifications read by the small model** (when you turned that on) never include one-time codes, bank, payment or password-manager notifications, nor anything that comes while the screen is locked or on Do Not Disturb.
- **Folders**: the allowed and writable folders can't be `/`, `/home`, your home or a folder holding it, nor anything in a hidden folder of your home (`~/.config`, `~/.ssh`, `~/.claude`…); such entries are ignored, for the side panel and the agents' desktop alike.
- Messages Claude said on its own (the **From Claude** tab) reach it, when you reply, marked as information that may quote third-party content, never as your request.

## Desktop memory

So the next task is faster, agents keep **notes** about your desktop — an app's shortcut, where a setting is, which app does what — and **recipes** (`run_steps` saved with `remember_as`). Usage is counted as they work, and `launch_app` learns **aliases** ("discord" → Vesktop).

Agents also learn the **controls** they use: a button, tab or menu item they pressed in an app is remembered with its place in the window, so next time `ui_act` reaches it by name in one call, without reading the window first. A control that moved is searched for again. Only short control names are learned, never list items, links or texts, whose names are content, and only from what agents do, never from your own clicks.

Only the relevant part reaches a model: when an agent connects it gets a short digest (aliases, most-used apps, the notes about the task in full, the other notes by topic only); notes about an app also arrive with the action that opens it. With 40 notes, the digest is about 165 tokens. Notes are labelled as hints written by agents, never your instructions.

It learns the way a person does, mostly in plain code, without spending a token:

- **What works gets stronger.** A note gets stronger when the task it was given for goes well (the agent's actions in that app worked) and weaker when it fails. Being shown to an agent doesn't count. Notes are ranked by how recently and how often they helped, the way human memory is (ACT-R's activation): several uses in one session count once, and uses spread over days count more. A note that keeps failing comes flagged, so the agent checks it, fixes it or forgets it.
- **What isn't used fades.** A note unused for 3 months (6 if it helped, a year if it helped often) moves to an **archive**. The digest stays short, and when an agent asks for that topic again, `recall` finds the note there and brings it back.
- **Recipes become habits.** `run_steps` with `remember_as` saves a recipe, with `{name}` placeholders (`vars`) for what changes. `run_recipe` runs it again in one call, so the steps never go through the model again. A recipe that worked on 3 days is a **macro**, offered in one line. A failing step demotes it, and the agent fixes that step.
- **Where a note came from.** Each note says whether an agent saw it work, you said it, or it was read in a page or message. A note read in content stays tentative until it works, and is never given unasked. No note can tell agents to ignore their rules or to send something somewhere, unless you said it.
- **Reminders.** "Remind me when I open Gmail to label the invoices", "…at 18:00": the `remind` tool keeps it with its cue (an app, words in a window title, a time). The shell shows a notification when the cue comes, once or every day.
- **A memory pass, only when it pays.** When an agent finished a task the memory knew nothing about and it took work (8 actions, or failures on the way), a small model (`memoryModel`, Haiku) reads it in the background afterwards. It sees what was asked and the actions in short, and what was typed only as its length. It may save a note or a recipe, tentative until it helps, plus **keywords** (the other words a task is asked with, so a search for "music" finds the Spotify note). Every other task costs no model call.
- **A weekly tidy-up**, like sleep: a small model merges notes on the same app or task that changed during the week (the merged note keeps what they proved), and gives keywords to the notes without them. There is no call when there is nothing to tidy.

`memoryLearn = false` turns the model passes off; the rest needs none.

- **Settings → Desktop agents** shows the notes (what each helped and failed, where it came from, recipes and macros; delete any), reminders, aliases, usage and learned controls, and clears them.
- `nixbook-desktop-mcp memory show|prompt|forget ID|fire ID|learn|tidy|clear`.
- Stored in `~/.local/state/nixbook-shell/desktop-memory.json` (private).

## Personal memory

Tell Claude in the side panel (or any agent) about your life — a trip you're planning, someone close to you, an event coming up — and later conversations know it. Agents keep **the meaningful part**, without asking: a few condensed facts, never a transcript, small talk, one-off requests or secrets. Ask them to remember or forget something, or what they know about you.

It is organised so it costs few tokens:

- **one entry per subject** ("japan", "work", "Lan (sister)"), at most 400 characters, merged as things change (agents must update the existing entry rather than add another);
- each entry is your **profile** (who you are: sent in every conversation, so kept short), a **person**, an **event** (with a date) or a **topic**;
- a conversation starts with your profile, the events coming up or just past, and the other subjects **by name only** (about 900 characters at most);
- when you talk about a subject, its entry comes with your message: say "I booked the flight to Kyoto" and the "japan" entry is there, so Claude can update it.

**People go in your contacts too.** An entry about someone ("Lan (sister)") is also written in the notes of their [contact](./accounts), under a _— Remembered by desktop agents —_ line, and kept in step as the entry changes: the contact with that name is found (or added, in the first account, when there is none), and your own notes above the line stay as they are. When several contacts have the name, the agent asks which. Forgetting the entry takes it off the contact. `personalContacts = false` turns this off; `personalContactsAccount` picks the account new contacts go in (e.g. `"local"`, kept on this computer).

**Naming someone finds them.** When you name a person ("ask Trang if Saturday works", "Élodie Martin's number"), the side panel's Claude gets their contacts with your message — how to reach them and what agents remember about them — so it knows who you mean. Other agents get them with the task, or search the contacts themselves. A full name matches in either order, a first name or nickname alone too (accents and case ignored; words that are also common words, like "May" or "Mai", only with a capital). When several contacts match or none does, the agent asks which one; once it knows who someone is to you, it remembers it, so next time it knows. `personalContacts = false` turns this off too.

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

## Usage habits

Off unless you turn it on: **Settings → Desktop agents → Usage habits → Learn from my usage** (or `nixbook-desktop-mcp habits on`; `programs.nixbook-shell.desktopMcp.habits.enable = true;` turns it on for good and locks the switch). The `nixbook-habits` user service then learns from **your own** use of the computer, counted on this machine in plain code: no model, no network.

- It counts which app has the focus and for how long, the windows you open, the [layouts](./window-layouts) you restore and the themes you choose.
- **App names and times only**: never window titles, files, sites, or anything you type (titles are read only to skip private windows, never stored). Two exceptions: the cues of [routines](#routines) learned from habits record device and network names (your headphones, your Wi-Fi), and your music taste (`habitsMusic`, on with habits) records each track's artist, title and album, kept a year (`habitsMusicKeepDays`).
- **Nothing is recorded** while the screen is locked, while you pause it, while an agent acts on the desktop, for password managers and password prompts (`habitsIgnoreApps`) or in private browser windows (`habitsIgnoreTitles`).
- It is kept **28 days** (`habitsKeepDays`), in `~/.local/state/nixbook-shell/habits.json` (private, 0600).
- It is light on the battery: the recorder sleeps until a window changes (a minute at most), appends a few bytes per app switch instead of rewriting its file (compacted once a day), and updates the launcher's ranking only when it changes, every 10 minutes at most. While off, nothing runs.

What it does with it:

- **Launcher**: apps you use at this hour, and the ones you usually open after the app in front of you, rank higher.
- **Your usual session**: agents get one line with the apps and layout you use around now, how your sessions start and your top apps this week. "Set up my work session" works without you listing what that means.
- **Your words for apps**: a word you type in the launcher before opening an app whose name doesn't contain it ("photo" → darktable) becomes, the second time, an alias agents' `launch_app` knows.
- **Weekly report**: a notification on Monday with the time per app, compared with the week before, the busiest day and the layouts used (`habitsWeeklyReport`). Also in Settings, and `nixbook-desktop-mcp habits report`.
- **Theme by time of day**: a theme you switched to at the same hour on 3 of the last 14 days is suggested then, with a Switch button (`habitsTheme`: `suggest`, `auto` to switch on its own, or `off`).
- **Open at the usual time**: apps you list in `habitsOpenAtUsualTime` (desktop ids) open on their own when you usually open them (on 3 of the last 4 same weekdays, within half an hour), once a day. None by default: a window appearing unasked is intrusive.
- **Your music taste**: what you play on **any player** — Spotify, YouTube Music, mpv, your phone through KDE Connect — is counted too: the artist, title and album of each track, and whether you listened (30 s or more) or skipped it. Agents then know your favourite artists, what you've been into lately (and which artists are new to you), your most played tracks, what you play around this hour and what you skip, so "play something I'd like" or "a playlist for the evening" works without you naming anything. Ads and podcast episodes aren't counted, nor web browsers (videos, not music: `habitsMusicIgnorePlayers`), but apps that publish under a browser's name, such as YouTube Music (an Electron app, `chromium.instanceN`), are, told apart by their player name (MPRIS Identity); music keeps being counted while the screen is locked. Kept a year (`habitsMusicKeepDays`); `habitsMusic = false` turns it off. `nixbook-desktop-mcp habits music` shows it, **Forget my music** (or `habits music-clear`) forgets it alone.
- **What did I do?**: `nixbook-desktop-mcp habits day [YYYY-MM-DD]` shows a day hour by hour. Agents get it only with `habitsAgents = "timeline"`.

What agents receive is set by `habitsAgents`: `digest` (the default: the line above and your favourite artists, and the `habits` tool's `now`, `week` and `music`), `timeline` (also a day hour by hour, when asked) or `off`. What agents receive goes to their model provider; the rest never leaves the machine.

- **Settings → Desktop agents → Usage habits** turns it on or off, pauses recording, shows what it learned and this week's report, and forgets everything.
- `nixbook-desktop-mcp habits on|off [--forget]|status|now|report [DAYS]|day [DATE]|music|music-clear|pause|resume|clear|show`.

```nix
programs.nixbook-shell.desktopMcp = {
  habits.enable = true; # optional: on for good, the Settings switch locked
  settings = {
    habitsAgents = "digest"; # or "timeline", "off"
    habitsTheme = "suggest"; # or "auto", "off"
    habitsOpenAtUsualTime = [ "vesktop" ];
  };
};
```

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

Written to `~/.config/nixbook-shell/desktop-mcp.json`; `nixbook-desktop-mcp config` prints what applies. Other keys tune screenshots (`screenshotFormat`, `screenshotQuality`, `screenshotMaxEdge`) and memory (`memoryPromptChars`, `memoryMaxNotes`, `memoryLearn`, `memoryModel`, `memoryClaude`, `personalPromptChars`, `personalMaxEntries`, `personalContacts`, `personalContactsAccount`).

The `ui` group needs the accessibility bus (`customNixOSModules.niri.accessibility`, on by default); the module sets the variables that make Firefox-based and Chromium/Electron apps publish their tree (apps started before need a restart).
