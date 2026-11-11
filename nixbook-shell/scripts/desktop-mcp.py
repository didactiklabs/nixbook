#!/usr/bin/env python3
"""nixbook-desktop-mcp: lets an AI agent see and drive the niri desktop.

A Model Context Protocol server (any MCP client: Claude Code, opencode,
Codex, …) and a command line for the shell's own AI chat, both
behind the same tools and the same guardrails:

  nixbook-desktop-mcp                       MCP over stdio (the client starts it)
  nixbook-desktop-mcp serve --http          MCP over HTTP, 127.0.0.1 only
  nixbook-desktop-mcp tools                 the tools, as MCP JSON
  nixbook-desktop-mcp call NAME [JSON]      run one tool (the shell's AI chat)
  nixbook-desktop-mcp pause|resume|status   the kill switch
  nixbook-desktop-mcp notify on|off|toggle  the "agent took over" notification

Guardrails (see README.md, "Desktop control for AI agents"):
  - no tool runs arbitrary commands: apps are launched from their .desktop
    entry, niri actions and shell IPC calls are a fixed, validated set;
  - tool groups can be turned off (config `tools`); `pause` stops every tool
    but `get_status` until `resume`, for every client at once; paused until
    the user first resumes, and the choice survives a reboot;
  - no keyboard or pointer input while the focused window is a terminal, a
    password manager or a password prompt (config `inputDenyApps`,
    `inputDenyTitles`); no Super combos (compositor bindings) or VT switches;
  - a rate limit on actions, a cap on typed text, a notification when an
    agent starts driving the desktop, an audit log of every call;
  - HTTP: bound to 127.0.0.1 only (loopback: no firewall rule needed, nothing
    off the machine can reach it), a bearer token in a 0600 file, the
    connecting process must belong to the same user (/proc/net/tcp), Host and
    Origin checked against DNS rebinding.

Standard library only; external tools: niri, grim, wtype, ydotool, wl-clipboard,
notify-send, and the shell's `qs` for its IPC.
"""

# The server is split by area into desktop-mcp/NN-area.py. They run here in
# order, in this module's namespace, as the one file they once were: a name
# defined in any part is visible in every other, and a test that replaces a
# function (`dm.niri_json = ...`) replaces it for all of them. The package
# (package.nix) joins them into one precompiled file instead.
import os as _desktop_mcp_os

_desktop_mcp_dir = _desktop_mcp_os.path.join(
    _desktop_mcp_os.path.dirname(_desktop_mcp_os.path.realpath(__file__)), "desktop-mcp")
for _desktop_mcp_part in sorted(n for n in _desktop_mcp_os.listdir(_desktop_mcp_dir) if n.endswith(".py")):
    _desktop_mcp_path = _desktop_mcp_os.path.join(_desktop_mcp_dir, _desktop_mcp_part)
    with open(_desktop_mcp_path, encoding="utf-8") as _desktop_mcp_file:
        exec(compile(_desktop_mcp_file.read(), _desktop_mcp_path, "exec"), globals())
