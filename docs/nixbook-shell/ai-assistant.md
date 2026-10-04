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
- It gets the MCP servers of `assistant.mcpServers` and only the built-in tools in `ai.claudeCode.allowedTools` (web search and fetch). **Running commands and editing files are refused.**
- **It reads none of your files** unless you allow it: _Folders AI agents may read_ (`ai.allowedFolders`, none by default) become read-only working directories, and a file attached to a message is readable on its own.
- It runs in an empty directory of its own, without your `~/.claude` settings, so permission rules from your own Claude Code sessions don't apply.
- **Use your claude.ai connectors** (`ai.claudeCode.connectors`, off by default) gives it the connectors of your Claude account (Gmail, Calendar, Drive…).

With a model selected, the configuration facts become reference for the model: it answers with its own knowledge too, and says when it isn't sure. `ai.includeSystemContext` (on by default; Settings → Services → AI) controls whether the machine context is sent.

## Translator

The sidebar's second tab translates text between languages.
