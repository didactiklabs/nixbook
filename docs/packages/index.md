# Custom packages

`customPkgs/` packages software that nixpkgs lacks, or needs at a different version. Every `customPkgs/<name>.nix` is exposed as **`pkgs.customPkgs.<name>`** by the overlay in `customPkgs/default.nix`, which `lib/pkgs.nix` adds for the machines, the tests and the docs. Their sources are pinned with [npins](/development/dependencies), and CI instantiates every one of them on each push.

| Package                                       | What it is                                                                      | Used by                        |
| --------------------------------------------- | ------------------------------------------------------------------------------- | ------------------------------ |
| [ginx](#ginx)                                 | Run a command whenever a Git repository changes                                 | `tools` (`osupdate`)           |
| [goji](#goji)                                 | Conventional Commits with emoji                                                 | `gojiConfig`                   |
| [rtk](#rtk)                                   | Shrinks command output for LLMs (60–90 % fewer tokens)                          | `rtk`                          |
| [opencode-manager](#opencode-manager)         | TUI for isolated coding-agent workspaces (`ocm`)                                | `devTools`, `ocmConfig`        |
| [openchoreo-cli](#openchoreo-cli)             | OpenChoreo developer platform CLI (`occ`)                                       | `devTools`                     |
| [crd-wizard](#crd-wizard)                     | Web/TUI dashboard for Kubernetes CRDs and custom resources                      | `kubeTools`                    |
| [kl](#kl)                                     | Interactive Kubernetes log viewer                                               | `kubeTools`                    |
| [sofka](#sofka)                               | A Kubernetes TUI in Rust                                                        | `kubeTools`                    |
| [kratix-cli](#kratix-cli)                     | Build Kratix Promises                                                           | `kubeTools`                    |
| [pvmigrate](#pvmigrate)                       | Migrate PVCs between StorageClasses                                             | `kubeTools`                    |
| [songbird](#songbird)                         | Evaluate Kubernetes network policies for connectivity                           | `kubeTools`                    |
| [witr](#witr)                                 | "Why is this running?" — trace a process, port, container or file to its origin | shell                          |
| [ytui](#ytui)                                 | Search YouTube and play in your local player                                    | `desktopApps`                  |
| [jtui](#jtui)                                 | Browse Jellyfin and play in your local player                                   | `desktopApps`                  |
| [fcitx5-lotus](#fcitx5-lotus)                 | Vietnamese input method for fcitx5                                              | `fcitx5-lotus`, `fcitx5Config` |
| [schnelle-umlaute](#schnelle-umlaute)         | German umlauts with a hold-letter + Space gesture                               | `fcitx5Config`                 |
| [actual-budget](#actual-budget)               | Local-first personal finance app (AppImage)                                     | profiles                       |
| [pear-desktop](#pear-desktop)                 | YouTube Music desktop player (nixpkgs build, native Wayland)                    | profiles                       |
| [youtube-music-mcp](#youtube-music-mcp)       | MCP server that plays and controls YouTube Music (pear-desktop)                 | `nixbookShellConfig`           |
| [spotify-mcp](#spotify-mcp)                   | MCP server that plays and controls the Spotify app                              | `nixbookShellConfig`           |
| [linkedin-mcp-server](#linkedin-mcp-server)   | MCP server for LinkedIn through your own browser session                        | `nixbookShellConfig`           |
| [immich-photo-manager](#immich-photo-manager) | MCP server for your Immich photo library                                        | `nixbookShellConfig`           |
| [kdeconnect-mcp](#kdeconnect-mcp)             | MCP server for your phone through KDE Connect: texts, sharing, notifications    | `nixbookShellConfig`           |
| [jellyfin-mcp](#jellyfin-mcp)                 | MCP server for your Jellyfin library and its players (mpv here, Moonfin, TVs)   | `nixbookShellConfig`           |
| [moonfin](#moonfin)                           | Jellyfin & Emby media client (AppImage)                                         | profiles                       |
| [cerbos](#cerbos)                             | Stateless authorization policy decision point (PDP)                             | profiles                       |

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

[Actual Budget](https://actualbudget.org), the local-first personal finance app, packaged from its release AppImage. Where nixbook-shell runs, totoro's profile starts it through the desktop agents' [Electron bridge](/nixbook-shell/desktop-agents#apps-and-browser-through-the-page) (`passthru.electronMarkers` names the extracted AppImage its processes run from).

## pear-desktop

[Pear Desktop](https://github.com/pear-devs/pear-desktop), a YouTube Music desktop player with extensions: nixpkgs' build (from source, on nixpkgs' Electron), wrapped by nixbook. It runs as a native Wayland client with GPU compositing — the release AppImage it replaced ran under XWayland in software and used three to five times the CPU, playing or paused. The launcher entry is named "YouTube Music", and the first launch turns off the app's beta **performance-improvement** plugin, whose "CPU Tamer" script restyles the page on every frame (~45% CPU); turning it back on from the app's Plugins menu is kept.

## youtube-music-mcp

An MCP server (source in `customPkgs/youtube-music-mcp/`) that lets an AI assistant search, play and queue songs and control playback in pear-desktop, through the app's own **API Server** plugin (no Google API key, no browser). `nixbookShellConfig` gives it to the nixbook-shell AI chat on every profile that installs pear-desktop.

To use it, turn on **Plugins → API Server** in the app (port 26538). On the first request the app asks to **Allow** the client `claude-mcp`; the token is then kept in `~/.config/youtube-music-mcp/token.json`. Playing a song needs something already loaded in the player. `YTM_API_URL`, `YTM_CLIENT_ID`, `YTM_TOKEN` and `YTM_TOKEN_FILE` override the defaults.

## spotify-mcp

An MCP server (source in `customPkgs/spotify-mcp/`) for the Spotify desktop app. `nixbookShellConfig` gives it to the nixbook-shell AI chat on every profile that installs Spotify.

- **Without setup**, through the app's MPRIS interface (playerctl): play, pause, next, previous, seek, volume, what's playing, and playing any `spotify:` uri or `open.spotify.com` link.
- **After a one-time `login`**, through the Spotify Web API: search (at most 10 results per call), play the first match for a query, the queue, your playlists, shuffle and repeat. Spotify's Development Mode needs your own app: create one at [developer.spotify.com/dashboard](https://developer.spotify.com/dashboard) with the Web API, redirect URI `http://127.0.0.1:8898/callback`, owned by a Premium account. Then ask the chat to log in to Spotify with its client ID: it opens the approval page in the browser and keeps the tokens in `~/.config/spotify-mcp/auth.json`.

`SPOTIFY_CLIENT_ID`, `SPOTIFY_REDIRECT_PORT` and `SPOTIFY_MCP_CONFIG` override the defaults.

## linkedin-mcp-server

[stickerdaniel/linkedin-mcp-server](https://github.com/stickerdaniel/linkedin-mcp-server) (4.25.1, the last release on the fastmcp 3 / mcp 1 that nixpkgs has), for the nixbook-shell AI chat only: profiles and people search, companies, messages, jobs and the feed, on your own LinkedIn account. `nixbookShellConfig` installs it (`linkedinMcp.enable`, on by default; `false` leaves it and its Chromium out), but the chat doesn't get it until you turn it on in **Settings → Desktop agents → Apps it can use**, where **Sign in to LinkedIn** opens its login window.

- It drives nixpkgs' Chromium (`CHROME_PATH`, so it never downloads a browser of its own) through [patchright](https://github.com/Kaliiiiiiiiii-Vinyzu/patchright-python), packaged from its PyPI wheel with nixpkgs' Node as its driver (nixpkgs' own patchright is marked broken). It doesn't check PyPI for updates.
- The session is kept in `~/.linkedin-mcp/profile`; `mcp-server-linkedin --login` and `--logout` sign in and out.
- LinkedIn's User Agreement forbids automated access and it may restrict accounts using such tools: the chat is told to use it sparingly, and to show a message or invitation and wait for your yes before sending it.

## kdeconnect-mcp

An MCP server (Go, source in `customPkgs/kdeconnect-mcp/`) for the phones paired with KDE Connect, talking to `kdeconnectd` on the session bus. `nixbookShellConfig` gives it to the nixbook-shell side panel's Muse, and only to it (and its routines), on every machine with `services.kdeconnect` (on by default): it isn't installed on the PATH, so your terminal Claude Code and other agents don't get it. Turn it off in **Settings → Desktop agents → Apps it can use** (**Phone**).

- **Always**: `devices` (reachable, battery, what each can do), `send_sms` (numbers, up to 5, 1600 characters), `share` (an http(s) link opened on the phone, or text to its share sheet; never a local file), `clipboard` (text on the phone's clipboard), `ring`, `ping`.
- **With Read my phone's texts and notifications** (`ai.phone.readMessages`, off by default; `KDECONNECT_MCP_READ=1`): `conversations` (threads, newest first, named from the contacts KDE Connect synced), `messages` (a thread), `notifications`, `reply_notification` (a messaging app's inline reply) and `contacts`.
- Muse is told to show the exact text and recipients and send only after your yes. Every send, share, clipboard and reply is logged, without its text, to `~/.local/state/kdeconnect-mcp/actions.log`.

## immich-photo-manager

[drolosoft/immich-photo-manager](https://github.com/drolosoft/immich-photo-manager) (2.0.13), for the nixbook-shell AI chat only: search your [Immich](https://immich.app) library by place, date, text and faces, albums, tags, duplicates, shared links, video frames and PDF reports. The chat starts it as a local stdio server: nothing listens on the network. `nixbookShellConfig` offers it on every machine, off until you turn it on.

Set it up in **Settings → Desktop agents → Apps it can use**: turn **Immich** on, enter the server URL and an API key (Immich: **Account Settings → API Keys**), then **Save and check**, which tries them on the server first. The URL is the `ai.immich.url` setting. The key goes to your keyring (`secret-tool`, `service=immich-photo-manager`), never into a file, the Nix store or a command line. Or set them in Nix, which locks them in Settings:

```nix
customHomeManagerModules.nixbookShellConfig.settings.ai = {
  immich = {
    url = "https://photos.example.org";
    apiKeyFile = "~/.config/immich/api-key"; # optional, instead of the keyring; or an agenix secret's path
  };
  claudeCode.mcpServersOff = [ "linkedin" ]; # Immich on
};
```

- The wrapper takes the key from `IMMICH_API_KEY`, else `apiKeyFile` (`~/` is your home; a store path fails an assertion), else the keyring. `immich-photo-manager-credentials status | save URL | forget` is what Settings calls (the key on stdin, never printed).
- Asked in the chat ("update my Immich credentials to …"), its `update_credentials` tool switches servers until you log out (it saves in `$XDG_RUNTIME_DIR`); **Save and check** clears that.
- It is built on the MCP Python SDK 2, which nixpkgs doesn't have yet: `mcp` 2.2.0 and `mcp-types` are packaged from their PyPI wheels next to it.
- The chat is told to say what would be deleted or shared, and wait for your yes, before deleting assets, emptying the trash or creating a public shared link.

## jellyfin-mcp

An MCP server (0.1.0, stdlib Python, source in `customPkgs/jellyfin-mcp/`) for your [Jellyfin](https://jellyfin.org) library and the players playing from it, for the nixbook-shell side panel's Muse (and so its speech bubble) only: it isn't installed on the PATH. `nixbookShellConfig` offers it where Moonfin is installed (`jellyfinMcp.enable`), off until you set it up.

- **Tools**: `search` (films, series, episodes, songs, albums, artists), `item` (details; a series' seasons and next episode, what a season, album or playlist holds), `continue_watching`, `next_up`, `recently_added`, `sessions` (the connected players, what each plays and how — direct play or transcoded, and why —, whether it takes remote control), `play` (an item, or a whole series, season, album, artist or playlist: now, next or last in the queue, from where you stopped; with audio and subtitles in a language asked for, or subtitles off), `control` (pause, unpause, toggle, stop, next, previous, seek, forward, back, volume, mute, fullscreen, and switching the audio or subtitle track), `track_preferences` (the user's default audio and subtitle languages and subtitle mode, for every player), `mark_played`, `favorite`, `playlists`, `playlist_add`.
- **Where it plays**: through the server, by default on this computer's player, [jellyfin-mpv-shim](https://github.com/jellyfin/jellyfin-mpv-shim) (`jellyfinMcp.player.enable`, the `jellyfin-mpv-shim` user service: your own mpv, fullscreen, no window or tray of its own; it saves progress, marks watched and goes on to the next episode). Moonfin, a TV or a browser when named, if it accepts remote control; other people's screens only when named.
- **The CLI** nixbook-shell uses: `configured`, `play-query TEXT` (the bubble's instant "play … season N episode M", no model: see [At once, without Muse](/nixbook-shell/desktop-agents#jellyfin)), `credentials status|login|save|test|forget` (`login URL USERNAME [--player]`: the password on stdin, signs in as that user and keeps the token; `save`/`test`: an admin's API key on stdin, checked on the server; `forget` ends a sign-in's session on the server), `shim-login URL USERNAME` (the password on stdin: signs the player in, then restarts it), `shim-status`, `shim-logout`.

Set it up in **Settings → Desktop agents → Apps it can use**: turn **Jellyfin** on, enter the server, then **Sign in** with your own Jellyfin username and password (an app password with two-factor authentication, e.g. the JellyfinSecurity plugin): no admin or API key needed. Muse gets a login of its own as you, in your keyring (`secret-tool`, `service=jellyfin-mcp`), and the player of this computer one of its own (`~/.config/jellyfin-mpv-shim/users.json`); the password isn't kept. An admin's API key (Jellyfin: **Dashboard → API Keys**, **Use an admin API key instead**) still works, for the user named in `ai.jellyfin.user`. The server can be set in Nix, which locks it in Settings:

```nix
customHomeManagerModules.nixbookShellConfig.settings.ai = {
  jellyfin = {
    url = "https://jellyfin.example.org";
    # Only with an admin's API key instead of a sign-in:
    # user = "khoa"; # empty: the first administrator
    # apiKeyFile = "~/.config/jellyfin/api-key"; # instead of the keyring; not a store path
  };
  claudeCode.mcpServersOff = [ "linkedin" "immich" ]; # Jellyfin on
};
```

The credential (a sign-in's token or an API key) comes from `JELLYFIN_API_KEY`, else `apiKeyFile` (`~/` is your home), else the keyring; which one it is is told by `GET /Users/Me`, which only a user's token answers. A token, a key or a password is never printed, logged, put in a tool result or on a command line. The player plays the files as they are: nixbook lifts jellyfin-mpv-shim's 10 Mbit/s limit for servers outside the local network (`jellyfinMcp.player.maxBitrateMbps` sets one). The package's install check runs every tool against a fake Jellyfin.

## seerr-mcp

An MCP server (0.1.0, stdlib Python, source in `customPkgs/seerr-mcp/`) for your [Seerr](https://github.com/seerr-team/seerr) (Overseerr / Jellyseerr), for the nixbook-shell side panel's Muse (and so its speech bubble) only: it isn't installed on the PATH. `nixbookShellConfig` offers it with Jellyfin (`seerrMcp.enable`), off until you set it up.

- **Tools**: `search` (films and series, each with its status: available, on its way, requested, not requested), `details` (a series' seasons each with its status, the requests), `request` (a film, or a series' seasons — every missing one by default —, 4K), `requests` (yours by default, filtered by status, with titles), `cancel_request`, `approve_request`, `decline_request`, `trending`, `upcoming`, `whoami` (who requests go out as, the quota left).
- **The CLI** nixbook-shell uses: `configured`, `login-from-browser URL` (your own login), `credentials status|save|test|forget` (the API key on stdin, checked on the server), `users URL` (to pick who requests go out as).

**Authentication**, two ways. **Your own login** (no admin key): sign in to Seerr in your browser as usual (OpenID Connect included) and `login-from-browser` takes only Seerr's session cookie (`connect.sid`, for that host) from its cookie file — Zen, Firefox, LibreWolf, Floorp (in clear), Chrome, Chromium, Brave, Vivaldi, Edge (decrypted with the browser's key from the keyring: `v10`/`v11`, AES-128-CBC in stdlib Python) —, checks it with `/auth/me` and keeps it in the keyring (`kind session`); seerr-mcp then acts as you until the session ends. **Or an admin's API key** (**Settings → General → API Key**, any login method): requests go out as `SEERR_USER` (a user id, name or email, sent as Seerr's `X-API-User`), shown as theirs and counted in their quota; without it, as the key's admin. Set it up in **Settings → Desktop agents → Apps it can use → Seerr**, or in Nix (the server and user; the key from the keyring or a file outside the store):

```nix
customHomeManagerModules.nixbookShellConfig.settings.ai.seerr = {
  url = "https://seerr.example.org";
  user = "khoa";
};
```

The credential comes from `SEERR_SESSION` or `SEERR_API_KEY`, else `SEERR_API_KEY_FILE` (`~/` is your home), else the keyring (`service=seerr-mcp`); it is never printed, logged, put in a tool result or on a command line. The package's install check runs every tool against a fake Seerr, and the browser login against fake Firefox and Chrome cookie files.

## moonfin

[Moonfin](https://github.com/Moonfin-Client/Moonfin-Core), a Jellyfin & Emby media client, packaged from its release AppImage (installed on every profile, kept opaque in niri and sway).

## cerbos

[Cerbos](https://cerbos.dev/), a stateless authorization policy decision point (PDP), packaged from its upstream prebuilt Linux x86_64 release tarball (which ships the `cerbos` and `cerbosctl` binaries) instead of building the large Go project from source.

## Adding a package

1. Add the source pin: `npins add github <owner> <repo>` (or `--branch main`).
2. Create `customPkgs/<name>.nix`, a function of `{ pkgs }` reading `(import ../npins).<name>`.
3. Use it as `pkgs.customPkgs.<name>` in a module.
4. `run-tests repo` instantiates every custom package.
