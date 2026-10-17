# Custom packages

`customPkgs/` packages software that nixpkgs lacks, or needs at a different version. Every `customPkgs/<name>.nix` is exposed as **`pkgs.customPkgs.<name>`** by the overlay in `customPkgs/default.nix`, which `lib/pkgs.nix` adds for the machines, the tests and the docs. Their sources are pinned with [npins](/development/dependencies), and CI instantiates every one of them on each push.

| Package                                     | What it is                                                                      | Used by                        |
| ------------------------------------------- | ------------------------------------------------------------------------------- | ------------------------------ |
| [ginx](#ginx)                               | Run a command whenever a Git repository changes                                 | `tools` (`osupdate`)           |
| [goji](#goji)                               | Conventional Commits with emoji                                                 | `gojiConfig`                   |
| [rtk](#rtk)                                 | Shrinks command output for LLMs (60–90 % fewer tokens)                          | `rtk`                          |
| [opencode-manager](#opencode-manager)       | TUI for isolated coding-agent workspaces (`ocm`)                                | `devTools`, `ocmConfig`        |
| [openchoreo-cli](#openchoreo-cli)           | OpenChoreo developer platform CLI (`occ`)                                       | `devTools`                     |
| [crd-wizard](#crd-wizard)                   | Web/TUI dashboard for Kubernetes CRDs and custom resources                      | `kubeTools`                    |
| [kl](#kl)                                   | Interactive Kubernetes log viewer                                               | `kubeTools`                    |
| [sofka](#sofka)                             | A Kubernetes TUI in Rust                                                        | `kubeTools`                    |
| [kratix-cli](#kratix-cli)                   | Build Kratix Promises                                                           | `kubeTools`                    |
| [pvmigrate](#pvmigrate)                     | Migrate PVCs between StorageClasses                                             | `kubeTools`                    |
| [songbird](#songbird)                       | Evaluate Kubernetes network policies for connectivity                           | `kubeTools`                    |
| [witr](#witr)                               | "Why is this running?" — trace a process, port, container or file to its origin | shell                          |
| [ytui](#ytui)                               | Search YouTube and play in your local player                                    | `desktopApps`                  |
| [jtui](#jtui)                               | Browse Jellyfin and play in your local player                                   | `desktopApps`                  |
| [fcitx5-lotus](#fcitx5-lotus)               | Vietnamese input method for fcitx5                                              | `fcitx5-lotus`, `fcitx5Config` |
| [schnelle-umlaute](#schnelle-umlaute)       | German umlauts with a hold-letter + Space gesture                               | `fcitx5Config`                 |
| [actual-budget](#actual-budget)             | Local-first personal finance app (AppImage)                                     | profiles                       |
| [pear-desktop](#pear-desktop)               | YouTube Music desktop player (AppImage)                                         | profiles                       |
| [youtube-music-mcp](#youtube-music-mcp)     | MCP server that plays and controls YouTube Music (pear-desktop)                 | `nixbookShellConfig`           |
| [spotify-mcp](#spotify-mcp)                 | MCP server that plays and controls the Spotify app                              | `nixbookShellConfig`           |
| [linkedin-mcp-server](#linkedin-mcp-server) | MCP server for LinkedIn through your own browser session                        | `nixbookShellConfig`           |
| [moonfin](#moonfin)                         | Jellyfin & Emby media client (AppImage)                                         | profiles                       |

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

## youtube-music-mcp

An MCP server (source in `customPkgs/youtube-music-mcp/`) that lets an AI assistant search, play and queue songs and control playback in pear-desktop, through the app's own **API Server** plugin (no Google API key, no browser). `nixbookShellConfig` gives it to the nixbook-shell AI chat on every profile that installs pear-desktop.

To use it, turn on **Plugins → API Server** in the app (port 26538). On the first request the app asks to **Allow** the client `claude-mcp`; the token is then kept in `~/.config/youtube-music-mcp/token.json`. Playing a song needs something already loaded in the player. `YTM_API_URL`, `YTM_CLIENT_ID`, `YTM_TOKEN` and `YTM_TOKEN_FILE` override the defaults.

## spotify-mcp

An MCP server (source in `customPkgs/spotify-mcp/`) for the Spotify desktop app. `nixbookShellConfig` gives it to the nixbook-shell AI chat on every profile that installs Spotify.

- **Without setup**, through the app's MPRIS interface (playerctl): play, pause, next, previous, seek, volume, what's playing, and playing any `spotify:` uri or `open.spotify.com` link.
- **After a one-time `login`**, through the Spotify Web API: search (at most 10 results per call), play the first match for a query, the queue, your playlists, shuffle and repeat. Spotify's Development Mode needs your own app: create one at [developer.spotify.com/dashboard](https://developer.spotify.com/dashboard) with the Web API, redirect URI `http://127.0.0.1:8898/callback`, owned by a Premium account. Then ask the chat to log in to Spotify with its client ID: it opens the approval page in the browser and keeps the tokens in `~/.config/spotify-mcp/auth.json`.

`SPOTIFY_CLIENT_ID`, `SPOTIFY_REDIRECT_PORT` and `SPOTIFY_MCP_CONFIG` override the defaults.

## linkedin-mcp-server

[stickerdaniel/linkedin-mcp-server](https://github.com/stickerdaniel/linkedin-mcp-server) (4.25.1, the last release on the fastmcp 3 / mcp 1 that nixpkgs has), for the nixbook-shell AI chat only: profiles and people search, companies, messages, jobs and the feed, on your own LinkedIn account. `nixbookShellConfig` installs it (`linkedinMcp.enable`, on by default; `false` leaves it and its Chromium out), but the chat doesn't get it until you turn it on in **Settings → Desktop agents → Apps it can use**. There, **Use my browser's session** takes the LinkedIn session of the browser you're signed in with (the most recently used one, checked with LinkedIn; the outcome comes as a notification), and **Sign in to LinkedIn** opens its own login window instead.

- It drives nixpkgs' Chromium (`CHROME_PATH`, so it never downloads a browser of its own) through [patchright](https://github.com/Kaliiiiiiiiii-Vinyzu/patchright-python), packaged from its PyPI wheel with nixpkgs' Node as its driver (nixpkgs' own patchright is marked broken). It doesn't check PyPI for updates.
- The session is kept in `~/.linkedin-mcp/profile`; `mcp-server-linkedin --login` and `--logout` sign in and out, `--import-from-browser [zen|firefox|chrome|…]` takes a browser's session.
- Upstream imports sessions from Chromium browsers only; a patch (`customPkgs/linkedin-mcp-server/gecko-import.patch`) adds Firefox-family ones: **Zen**, Firefox, LibreWolf and Floorp (their `profiles.ini` and plain-text `cookies.sqlite`, the default container's cookies). The same import runs on its own on the first request needing a session.
- LinkedIn's User Agreement forbids automated access and it may restrict accounts using such tools: the chat is told to use it sparingly, and to show a message or invitation and wait for your yes before sending it.

## moonfin

[Moonfin](https://github.com/Moonfin-Client/Moonfin-Core), a Jellyfin & Emby media client, packaged from its release AppImage (installed on every profile, kept opaque in niri and sway).

## Adding a package

1. Add the source pin: `npins add github <owner> <repo>` (or `--branch main`).
2. Create `customPkgs/<name>.nix`, a function of `{ pkgs }` reading `(import ../npins).<name>`.
3. Use it as `pkgs.customPkgs.<name>` in a module.
4. `run-tests repo` instantiates every custom package.
