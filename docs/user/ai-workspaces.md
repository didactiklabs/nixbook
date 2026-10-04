# AI coding workspaces (ocm)

[opencode-manager](https://mickael-roger.github.io/opencode-manager/) (`ocm`) is a k9s-style TUI that creates, attaches to, edits and tears down **isolated workspaces for coding agents** (OpenCode, Claude Code) in containers. Nixbook packages a fork of it and configures it declaratively with `customHomeManagerModules.ocmConfig`.

```nix
customHomeManagerModules.ocmConfig = {
  enable = true;
  kubeswitch.enable = true;          # offer host kube contexts to workspaces
  desktopMemory.enable = true;       # nixbook-shell's desktop memory, read-only
  notificationHistory.enable = true; # nixbook-shell's notification history
};
```

## What it configures

- `~/.config/opencode-manager/config.yaml` with **`runtime: podman`** (Podman is installed system-wide) and the **base image** every workspace is built from — the prebuilt `ocm-base` (npx, uvx, git, ripgrep, jq, opencode, claude) plus a thin local layer:
  - `baseImage.packages` — extra apt packages;
  - `baseImage.commands` — extra build commands, run as root.
- **Nix and devenv inside workspaces** (`nix.enable`, `nix.devenv`, on by default): Debian's Nix, a single-user configuration that works under rootless Podman, and devenv on every process's `PATH`. Pin `nix.nixpkgs` to make the image rebuild reproducibly.
- **Shared agent instructions** (`agentInstructions`): one `AGENTS.md` synced into every workspace for OpenCode — and, with `claudeCode.importAgentInstructions`, imported by Claude Code too, so both agents follow the same rules. The default asks agents to prefer devenv / `nix shell`, follow project conventions, run tests and never commit unasked.
- **Shared OpenCode settings** (`opencodeSettings`): the host's OpenCode auth plugins, so workspaces authenticate the same way.

The config file is a store symlink, so `ocm config edit` cannot change it — change the Nix options instead (or delete the file to take manual control until the next activation).

## Modules for workspaces

ocm _modules_ add capabilities to a workspace; nixbook installs these, and you add them per workspace from ocm's module editor:

| Module                       | Option                       | Gives the workspace                                                                                                                                  |
| ---------------------------- | ---------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `infra/kubeswitch`           | `kubeswitch.enable`          | Pick host kubeswitch contexts; each is exported minified (credentials inlined) and merged into the workspace's `~/.kube/config`. Nothing is mounted. |
| `tools/host-display`         | `hostDisplay.enable` (on)    | The host's Wayland (and XWayland) session: agents can launch GUI apps and take screenshots (`ocm-screenshot`).                                       |
| `tools/notification-history` | `notificationHistory.enable` | A live, read-only copy of nixbook-shell's notification history (`host-notifications -n 20 -a Slack`).                                                |
| `tools/desktop-memory`       | `desktopMemory.enable`       | nixbook-shell's [desktop memory](/nixbook-shell/desktop-agents#desktop-memory), read-only (`host-memory wifi`).                                      |
| `tools/mcp-nixos`            | `mcpNixos.enable` (on)       | [MCP-NixOS](https://mcp-nixos.io) registered with the workspace's Claude Code: real package and option data.                                         |

::: warning host-display
A workspace with the host display can capture your whole desktop. Add it only to workspaces you trust. The socket is bound by inode, so restart the workspace after logging in again.
:::

Each workspace logs in to Claude Code once (`claude /login`); the login lives in the workspace's home and survives container recreation. The host's login is deliberately not shared, because OAuth refresh tokens rotate.
