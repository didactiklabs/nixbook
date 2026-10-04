# Development tools

## Dev tools

`customHomeManagerModules.devTools` installs a curated development and DevOps set:

| Category               | Tools                                                                             |
| ---------------------- | --------------------------------------------------------------------------------- |
| Languages & build      | Python 3, GNU make, Go (via the user environment, `GOPATH` set)                   |
| Nix                    | devenv, devbox, npins, nix-eval-jobs, nixos-generators                            |
| Infrastructure as code | Terraform, MinIO client, Google Cloud SDK (with the GKE auth plugin)              |
| Code generation & APIs | cobra-cli, openapi-generator-cli, templ, Bruno (+ CLI)                            |
| AI assistants          | Claude Code, Antigravity CLI (`agy`), [opencode-manager](./ai-workspaces) (`ocm`) |
| Utilities              | go-task (Taskfile), runme (runnable Markdown), OpenChoreo CLI (`occ`)             |

## Git

`customHomeManagerModules.gitConfig`:

- Git with LFS; `pull.rebase`, `push.autoSetupRemote`, `main` as default branch, prune on fetch;
- **difftastic** — a syntax-aware structural diff — as Git's diff driver;
- GitHub CLI with the `gh-eco`, `gh-notify`, `gh-poi` and `gh-f` extensions, and **gh-dash** with sections for the organisation's PRs, your PRs, reviews and participation;
- `tig`, `git-extras`;
- aliases:

| Alias        | Does                                  |
| ------------ | ------------------------------------- |
| `lg`         | Graph log                             |
| `s` / `d`    | Status / diff                         |
| `sw`, `swcr` | Switch / create and switch            |
| `save`       | Add all and commit                    |
| `undo`       | Undo the last commit (keep changes)   |
| `lazy`       | Add, commit and push                  |
| `pushmr`     | New branch, commit and push for an MR |
| `purge`      | Delete merged branches                |

Per-user identity and signing go in the profile (`profiles/<host>/<user>/gitConfig.nix`).

## Goji

`customHomeManagerModules.gojiConfig` installs [goji](https://github.com/muandane/goji) for **Conventional Commits with emoji** (`✨ feat(scope): subject`), and **`goji-ai`**, which sends the staged diff to OpenCode and fills in type, scope and subject for you:

```bash
git add -p
goji-ai            # or: goji-ai -t fix -s installer, --amend, -a (add all)
```

Shell shortcuts: `gfix`, `gfeat`, `gchore`. `goji-ai` needs `opencodeConfig`.

## NixVim

`customHomeManagerModules.nixvimConfig` — Neovim configured entirely in Nix, set as the default editor (`vi`/`vim` aliases):

- **LSP** (gopls, nil, TypeScript, Python, Lua…), nvim-cmp completion, none-ls formatters and linters, Treesitter;
- **Telescope**, **neo-tree**, **trouble**;
- editing: comment, mini.nvim (surround, pairs…), git-conflict, trim;
- UI: barbar, lualine, noice, notify, snacks, smear-cursor, neoscroll, colorizer, markdown-preview, floaterm, startify;
- **OpenCode** integration and ThePrimeagen's **99** plugin; Discord presence (neocord);
- Space as leader, the Wayland clipboard, persistent undo, French spell-check dictionaries.

See the [Neovim keybindings](/desktop/keybindings#neovim-nixvim).

## VS Code

`customHomeManagerModules.vscode` — VS Code with an **immutable, pinned extension set** (200+ extensions: Go, Rust, Python, TypeScript, Nix, Terraform, Kubernetes, Helm, Ansible, Docker…, GitHub Copilot, GitLens, Error Lens…), format-on-save (golines, nixfmt), and kitty as the external terminal. `homeManagerModules/vscode/update_extensions.sh` refreshes the extension list.

## OpenCode

`customHomeManagerModules.opencodeConfig` configures the [OpenCode](https://opencode.ai) terminal coding assistant with Google (Gemini) and Anthropic (Claude) OAuth plugins. Other modules build on it: `goji-ai`, RTK's OpenCode hook, and the DMS usage widget. Profiles add MCP servers through `programs.opencode.settings.mcp`.

## RTK

`customHomeManagerModules.rtk` installs [RTK](/packages/#rtk), a CLI proxy that compresses the output of common commands (git, kubectl, terraform…) before it reaches an LLM — **60–90 % fewer tokens** on typical workflows. Its hooks are registered globally on activation, and wired into OpenCode when `opencodeConfig` is on.

## Bitwarden (rbw)

`customHomeManagerModules.rbwConfig` configures [rbw](https://github.com/doy/rbw), the unofficial Bitwarden CLI, against a self-hosted server:

```nix
customHomeManagerModules.rbwConfig = {
  enable = true;
  email = "you@example.com";
  baseUrl = "https://pass.example.com";
};
```

## Containers

Podman (with the `docker` alias) is installed system-wide by the [`tools` module](/system/core#the-tools-module). See also [AI coding workspaces](./ai-workspaces), which run agents in Podman containers.
