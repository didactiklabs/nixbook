# AI chat & config assistant

The **left sidebar** (Mod+Space) holds a chat with two models:

| Model                          | What it is                                                                          |
| ------------------------------ | ----------------------------------------------------------------------------------- |
| **Config assistant** (default) | Offline, no AI: answers instantly from this machine's configuration                 |
| **Claude** (`/model claude`)   | Claude Code on your own Claude login — no API key — with the desktop tools attached |

## Config assistant

The config assistant answers from facts generated from your evaluated configuration, in **English, French, German and Vietnamese** (detected from the question), in under 100 ms:

- **key bindings**: "how do I open the launcher?", "what does Mod+R do?", "all vim shortcuts" (NixVim's real keymaps, overrides included);
- **your system**: NixOS release, kernel, host, time zone, locale, keyboard layout, bootloader, shell, editor;
- **"is X enabled?"** for every module option with an `enable` switch, and "is X installed?" for packages;
- **shell settings**: "what does `bar.bottom` do?", and the settings pinned in Nix;
- **how-tos**: updating, rolling back, freeing disk space, syncing your calendar, stopping the desktop agents, window layouts, Claude in the panel…

`/help` (or "help", "aide", "hilfe", "giúp") lists the kinds of questions it answers. When nothing matches exactly, it shows the closest facts; off-topic questions get "I don't know" and tips. Answers are selectable and copyable.

### Teaching it about your machine

`programs.nixbook-shell.assistant` controls what it — and Claude — knows:

| Option       | What                                                                                                      |
| ------------ | --------------------------------------------------------------------------------------------------------- |
| `context`    | Free text about the machine (nixbook fills in host, enabled modules, profile paths, how to deploy)        |
| `coreFacts`  | Key statements always included                                                                            |
| `niriConfig` | Niri's bindings, turned into "Press Mod+D to open the app launcher" facts                                 |
| `nixvim`     | NixVim keymaps and leader (default: the evaluated ones)                                                   |
| `os`         | System facts                                                                                              |
| `howTo`      | Named how-to answers; set one to your own way (a deploy tool, an update script) or `null` to drop it      |
| `mcpServers` | MCP servers given to Claude (default: [MCP-NixOS](https://mcp-nixos.io) for real package and option data) |

On NixOS, add the shell's `nixosModules.default` so "is X enabled?" also covers system options (Home Manager modules only see the NixOS configuration, not its options). nixbook does this for you.

## Claude in the side panel

When Claude Code is installed (`claude` on the PATH, in `~/.local/bin` or a Nix profile), the chat offers **Claude**. Set it up in **Settings → Desktop agents → Claude in the side panel**:

- whether Claude Code was found (and its command if elsewhere);
- the model — **Sonnet** by default, or Opus, Haiku, or Claude Code's own — and thinking effort (low by default: desktop tasks are many short steps);
- whether it may search and read the web;
- the folders it may read.

Replies stream in, each tool call shows with its result in a collapsible block, and the send button (or `/stop`) stops the answer. Claude Code keeps running between messages, so replies start immediately; it closes after 15 minutes unused.

### What Claude can and can't do

- It drives the desktop through the [desktop control tools](./desktop-agents) — with their guardrails, the pause button and the memory.
- It remembers what you tell it about your life across conversations — the [personal memory](./desktop-agents#personal-memory): one short entry per subject, and only the entries about what you're talking about come with your message.
- It gets the MCP servers of `assistant.mcpServers` and only the built-in tools in `ai.claudeCode.allowedTools` (web search and fetch). **Running commands is refused.**
- **It reads none of your files** unless you allow it: _Folders AI agents may read_ (`ai.allowedFolders`, none by default) become read-only working directories, and a file attached to a message is readable on its own.
- **It writes files only where you let it**: in _Folders AI agents may write_ (`ai.writableFolders`, none by default) it can create and edit files; anywhere else is refused.
- It runs in an empty directory of its own, without your `~/.claude` settings, so permission rules from your own Claude Code sessions don't apply.
- **Command line and terminal** (`ai.claudeCode.commandLine`, off by default): Claude may run commands on this computer as you (Claude Code's Bash tool), and its desktop tools may type into terminal windows and open terminal apps (only this chat's: other agents still may not; password managers and password prompts stay off limits). It looks around freely but says exactly what it will run, and waits for your yes in the chat, before anything that changes the system or your files: installing, removing or editing files, `sudo`, `systemctl`, git commits or pushes, NixOS switches, sending data off the machine. With it on, Claude can read any of your files, whatever the folders listed.
- **Speak as this computer** (`ai.claudeCode.asComputer`, on by default): Claude answers as the machine itself — "my CPU is an AMD Ryzen 7 6800U", "my battery is at 80%, though its health is down to 46%" — reading its hardware, OS and kernel live through the desktop tools' `system_info` rather than guessing.
- **Use your claude.ai connectors** (`ai.claudeCode.connectors`, off by default) gives it the connectors of your Claude account (Gmail, Calendar, Drive…) and the plugins you enabled on claude.ai (Hunter…), loaded from Claude Code's synced copy (`~/.claude/plugins/synced`) each time it starts, since the panel leaves your own Claude Code settings out. They are listed again each time the panel opens, and a connector Claude Code finds that the chat didn't know of yet (added on claude.ai with the panel open) is allowed on the spot: Claude starts again on the same message. **Reload connectors** (or `nixbook-shell ipc call ai reloadConnectors`) restarts it by hand, keeping the conversation; use it after signing in to a connector on claude.ai (Claude Code would otherwise skip a connector that needed signing in for 4 hours).

With a model selected, the configuration facts become reference for the model: it answers with its own knowledge too, and says when it isn't sure. `ai.includeSystemContext` (on by default; Settings → Services → AI) controls whether the machine context is sent.

## Tabs

The chat has **tabs**, each its own conversation answering on its own, so Claude can work on several things at once: **+** above the chat (or **Ctrl+T**) opens one, **Ctrl+Tab** / **Ctrl+Shift+Tab** go through them, and **×**, a middle-click or **Ctrl+W** closes one (its conversation stays in the history). A tab shows a spinner while it works and a dot when it answered while you were elsewhere; when the panel is closed, the notification's **Open** opens that tab. Up to 8 tabs.

Each tab runs its own Claude Code. When agents work on [their own desktop](./agent-desktop), each tab also gets **its own desktop**, so they don't fight over one pointer and keyboard: the first tab uses "Assistant's desktop", the others "Assistant's desktop 2", "3"… (the number shows on the tab). Closing a tab closes its desktop.

## Conversations

Every conversation is saved as you chat, after each answer. The **history** button at the top of the chat (or **Ctrl+H**, or `/history`) lists them — pinned first, then by day — to go back to one:

- **click** one to open it (in its tab, if a tab has it open; the **tab** button or a middle-click opens it in a new one); with Claude, it resumes the same Claude Code session when Claude Code still has it (it keeps sessions about a month), otherwise the conversation so far goes with your next message;
- **search** by title; Up/Down and Enter open one from the keyboard, Esc goes back;
- **rename** one (its pencil, or right-click), **pin** it to keep it for good, or **delete** it; **Delete all** deletes every conversation but the pinned ones (click twice);
- **New conversation** (the button beside the token count, or `/clear`) starts a fresh one; the current one stays in the history.

Conversations are deleted **30 days after their last message**, unless pinned. Change that in **Settings → Services → AI** (_Keep conversations for_, `ai.history.keepDays`; `0` keeps them until you delete them), which also deletes them all but the pinned ones. They're stored in `~/.local/state/quickshell/user/ai/history/`.

## Translator

The sidebar's second tab translates text between languages.
