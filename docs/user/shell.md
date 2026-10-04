# Shell & terminal

## Zsh

`customHomeManagerModules.zshConfig` gives a fast, batteries-included Zsh:

- oh-my-zsh-style defaults (key bindings, completion menu, directory options) **without** oh-my-zsh, to keep startup fast;
- syntax highlighting, fish-style **autosuggestions**, auto-pairing, `zsh-bat` (coloured `cat`);
- **any-nix-shell**: `nix shell` and `nix develop` keep Zsh instead of dropping to bash.

### Shared integrations and modern replacements

From `commonShellConfig` (part of every shell setup):

| Tool                                            | Replaces / does                                       | Alias      |
| ----------------------------------------------- | ----------------------------------------------------- | ---------- |
| [atuin](https://atuin.sh)                       | Searchable shell history (Ctrl+R; Up arrow untouched) | —          |
| [zoxide](https://github.com/ajeetdsouza/zoxide) | Smarter `cd`                                          | `cd` → `z` |
| [eza](https://eza.rocks)                        | `ls`                                                  | —          |
| [bat](https://github.com/sharkdp/bat)           | `cat` with syntax highlighting                        | —          |
| [yazi](https://yazi-rs.github.io)               | Terminal file manager                                 | `y`        |
| [fzf](https://github.com/junegunn/fzf)          | Fuzzy finder                                          | —          |
| [direnv](https://direnv.net) + nix-direnv       | Per-directory environments                            | —          |
| viddy                                           | `watch`                                               | `watch`    |
| duf                                             | `df`                                                  | `df`       |
| dgop                                            | `top`                                                 | `top`      |
| trippy                                          | traceroute / mtr                                      | —          |
| sd                                              | `sed` for replacements                                | —          |
| fastfetch                                       | neofetch                                              | `neofetch` |

Also: `ks` → `kswitch`, and the Goji shortcuts `gfix`, `gfeat`, `gchore` ([Development](./development#goji)).

## Starship prompt

`customHomeManagerModules.starship` — a two-line prompt coloured from the Stylix palette:

```
[nix_shell] user@host ☸ k8s-context in ~/…/path  branch [⇡+!?]
❯
```

It shows whether you are in a (pure/impure) Nix shell, the current **Kubernetes context**, the directory (truncated, 🔒 when read-only), the Git branch and status; the arrow turns red after a failing command. Slow modules (time, package, python, git metrics) are off.

## Atuin history sync

Atuin is always on. `customHomeManagerModules.atuinConfig.didactiklabs.enable` additionally syncs history across machines through the DidactikLabs Atuin server (record-based sync; Enter runs the selected entry).

## Kitty

`customHomeManagerModules.kittyConfig` — the GPU-accelerated terminal, bound to **Mod+Return** in Niri and Sway:

- Roboto Mono 10 pt, copy-on-select, a cursor trail, a powerline tab bar at the bottom;
- **splits** instead of tmux:

| Keys                                | Action                      |
| ----------------------------------- | --------------------------- |
| `Ctrl+Shift+S` / `Ctrl+Shift+Enter` | Vertical / horizontal split |
| `Alt+←/→/↑/↓`                       | Move between splits         |
| `Shift+←/→/↑/↓`                     | Move / reorder splits       |
| `Ctrl+Shift+←/→`                    | Previous / next tab         |
| `Ctrl+Shift+W`                      | Close tab                   |

- `ssh` sets `TERM=xterm-256color` for remote hosts; `sshs` uses kitty's ssh kitten;
- VS Code uses kitty as its external terminal; ranger shows image previews.

## CLI tools

`customHomeManagerModules.cliTools` — small essentials: `jq`, `yq`, `unzip`, `wget`, `dig`, `tree`. Container and Kubernetes tools live in [Kubernetes](./kubernetes).

## Fastfetch

`customHomeManagerModules.fastfetchConfig` — a boxed system summary (OS, kernel, packages, WM, terminal, shell / host, CPU, GPU, memory, disk) with a custom NixOS snowflake logo. Profiles can ship their own variant (`profiles/<host>/fastfetchConfig.nix`).
