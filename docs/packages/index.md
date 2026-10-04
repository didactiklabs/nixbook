# Custom packages

`customPkgs/` packages software that nixpkgs lacks, or needs at a different version. Every `customPkgs/<name>.nix` is exposed as **`pkgs.customPkgs.<name>`** by the overlay in `customPkgs/default.nix`, which `lib/pkgs.nix` adds for the machines, the tests and the docs. Their sources are pinned with [npins](/development/dependencies), and CI instantiates every one of them on each push.

| Package                               | What it is                                                                      | Used by                        |
| ------------------------------------- | ------------------------------------------------------------------------------- | ------------------------------ |
| [ginx](#ginx)                         | Run a command whenever a Git repository changes                                 | `tools` (`osupdate`)           |
| [goji](#goji)                         | Conventional Commits with emoji                                                 | `gojiConfig`                   |
| [rtk](#rtk)                           | Shrinks command output for LLMs (60–90 % fewer tokens)                          | `rtk`                          |
| [opencode-manager](#opencode-manager) | TUI for isolated coding-agent workspaces (`ocm`)                                | `devTools`, `ocmConfig`        |
| [openchoreo-cli](#openchoreo-cli)     | OpenChoreo developer platform CLI (`occ`)                                       | `devTools`                     |
| [crd-wizard](#crd-wizard)             | Web/TUI dashboard for Kubernetes CRDs and custom resources                      | `kubeTools`                    |
| [kl](#kl)                             | Interactive Kubernetes log viewer                                               | `kubeTools`                    |
| [sofka](#sofka)                       | A Kubernetes TUI in Rust                                                        | `kubeTools`                    |
| [kratix-cli](#kratix-cli)             | Build Kratix Promises                                                           | `kubeTools`                    |
| [pvmigrate](#pvmigrate)               | Migrate PVCs between StorageClasses                                             | `kubeTools`                    |
| [songbird](#songbird)                 | Evaluate Kubernetes network policies for connectivity                           | `kubeTools`                    |
| [witr](#witr)                         | "Why is this running?" — trace a process, port, container or file to its origin | shell                          |
| [ytui](#ytui)                         | Search YouTube and play in your local player                                    | `desktopApps`                  |
| [jtui](#jtui)                         | Browse Jellyfin and play in your local player                                   | `desktopApps`                  |
| [fcitx5-lotus](#fcitx5-lotus)         | Vietnamese input method for fcitx5                                              | `fcitx5-lotus`, `fcitx5Config` |
| [schnelle-umlaute](#schnelle-umlaute) | German umlauts with a hold-letter + Space gesture                               | `fcitx5Config`                 |
| [actual-budget](#actual-budget)       | Local-first personal finance app (AppImage)                                     | profiles                       |
| [pear-desktop](#pear-desktop)         | YouTube Music desktop player (AppImage)                                         | profiles                       |

## ginx

[didactiklabs/ginx](https://github.com/didactiklabs/ginx) watches a remote Git repository and runs a command against it on changes. Nixbook uses it to deploy the latest `main`:

```bash
ginx --source https://github.com/didactiklabs/nixbook -b main --now -- colmena apply-local --sudo
```

## goji

[muandane/goji](https://github.com/muandane/goji) — a commitizen-like tool for emoji Conventional Commits. Wrapped by `goji-ai`, see [Development tools](/user/development#goji).

## rtk

[rtk-ai/rtk](https://github.com/rtk-ai/rtk) — a CLI proxy that compresses the output of common dev commands before it reaches an LLM. See [Development tools](/user/development#rtk).

## opencode-manager

A k9s-style TUI to create, attach, edit and tear down isolated OpenCode / Claude Code workspaces in containers. Nixbook pins a fork with fixes not yet upstream, reported as `v<base>-fork.<rev>`. See [AI coding workspaces](/user/ai-workspaces).

## openchoreo-cli

`occ`, the CLI of [OpenChoreo](https://github.com/openchoreo/openchoreo), an internal developer platform for Kubernetes.

## crd-wizard

[pehlicd/crd-wizard](https://github.com/pehlicd/crd-wizard) — a web and TUI dashboard to explore CRDs and their custom resources. Opened from k9s with **Shift+E**.

## kl

[robinovitch61/kl](https://github.com/robinovitch61/kl) — an interactive multi-pod Kubernetes log viewer for the terminal.

## sofka

[nklmilojevic/sofka](https://github.com/nklmilojevic/sofka) — a Kubernetes TUI reimagined in Rust, aliased `ki`.

## kratix-cli

[syntasso/kratix-cli](https://github.com/syntasso/kratix-cli) — build [Kratix](https://kratix.io) Promises.

## pvmigrate

[replicatedhq/pvmigrate](https://github.com/replicatedhq/pvmigrate) — migrate PersistentVolumeClaims between StorageClasses.

## songbird

[banh-canh/songbird](https://github.com/banh-canh/songbird) — evaluates Kubernetes network policies to check connectivity between workloads.

## witr

[pranshuparmar/witr](https://github.com/pranshuparmar/witr) — "Why is this running?": trace any process, port, container or file back to what started it (CLI and TUI).

## ytui

[banh-canh/ytui](https://github.com/banh-canh/ytui) — query YouTube videos from a TUI and play them in your local player (mpv).

## jtui

[banh-canh/jtui](https://github.com/banh-canh/jtui) — browse a Jellyfin server from a TUI and play in your local player.

## fcitx5-lotus

[LotusInputMethod/fcitx5-lotus](https://github.com/LotusInputMethod/fcitx5-lotus) — Vietnamese input for fcitx5. See [Input methods](/system/input-methods#vietnamese-lotus).

## schnelle-umlaute

[Maik-0000FF/schnelle-umlaute](https://github.com/Maik-0000FF/schnelle-umlaute) — German umlauts with a hold-letter + Space gesture. See [Input methods](/system/input-methods#german-schnelle-umlaute).

## actual-budget

[Actual Budget](https://actualbudget.org), the local-first personal finance app, packaged from its release AppImage.

## pear-desktop

[Pear Desktop](https://github.com/pear-devs/pear-desktop), a YouTube Music desktop player with extensions, packaged from its release AppImage.

## Adding a package

1. Add the source pin: `npins add github <owner> <repo>` (or `--branch main`).
2. Create `customPkgs/<name>.nix`, a function of `{ pkgs }` reading `(import ../npins).<name>`.
3. Use it as `pkgs.customPkgs.<name>` in a module.
4. `run-tests repo` instantiates every custom package.
