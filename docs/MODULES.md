# Nixbook Custom Module Options

> **Auto-generated** from the Nix module definitions.
> Run `nix-build docs/generate-docs.nix && cp result/MODULES.md docs/MODULES.md` to regenerate.

## Table of Contents

### NixOS Modules

- [caCertificates](#cacertificates)
- [core](#core)
- [firewall](#firewall)
- [getRevision](#getrevision)
- [greetd](#greetd)
- [hyprland](#hyprland)
- [laptopProfile](#laptopprofile)
- [netbird-tools](#netbird-tools)
- [niri](#niri)
- [printTools](#printtools)
- [sunshine](#sunshine)
- [sway](#sway)
- [tailscale](#tailscale)
- [tools](#tools)
- [vmSupport](#vmsupport)

### Home Manager Modules

- [atuinConfig](#atuinconfig)
- [cliTools](#clitools)
- [desktopApps](#desktopapps)
- [devTools](#devtools)
- [dmsConfig](#dmsconfig)
- [fastfetchConfig](#fastfetchconfig)
- [fcitx5Config](#fcitx5config)
- [fontConfig](#fontconfig)
- [gitConfig](#gitconfig)
- [gojiConfig](#gojiconfig)
- [gtkConfig](#gtkconfig)
- [hyprlandConfig](#hyprlandconfig)
- [kittyConfig](#kittyconfig)
- [kubeConfig](#kubeconfig)
- [kubeTools](#kubetools)
- [kubeswitchConfig](#kubeswitchconfig)
- [niriConfig](#niriconfig)
- [nixvimConfig](#nixvimconfig)
- [opencodeConfig](#opencodeconfig)
- [rtk](#rtk)
- [sshConfig](#sshconfig)
- [starship](#starship)
- [stylixConfig](#stylixconfig)
- [swayConfig](#swayconfig)
- [thunderbirdConfig](#thunderbirdconfig)
- [volumeScript](#volumescript)
- [vscode](#vscode)
- [zshConfig](#zshconfig)

---

# NixOS Modules (`customNixOSModules`)

## caCertificates

### `customNixOSModules.caCertificates.bealv.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to install the Bealv internal CA certificate system-wide. Adds assets/certs/bealv-ca.crt to the system PKI trust store and exposes it at /etc/ssl/certs/bealv-ca.crt so tools like curl, git, and browsers trust internal Bealv HTTPS endpoints without warnings.

### `customNixOSModules.caCertificates.didactiklabs.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to install the DidactikLabs internal CA certificate system-wide. Adds assets/certs/didactiklabs-ca.crt to the system PKI trust store and exposes it at /etc/ssl/certs/didactiklabs-ca.crt so all system tools trust internal DidactikLabs HTTPS endpoints (e.g. the Atuin sync server, private container registries, etc.).

### `customNixOSModules.caCertificates.logicmg.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to install the LogicMG internal CA certificate system-wide. Adds assets/certs/logicmg-ca.crt to the system PKI trust store so all system tools trust internal LogicMG HTTPS endpoints. Used on: nishinoya (aamoyel's machine).

---

## core

### `customNixOSModules.core.enable`

- **Type:** `boolean`
- **Default:** `true`

Whether to enable the core NixOS module. This is the foundational system module that configures: - Boot: systemd-boot UEFI loader, plymouth splash screen, latest kernel, LVM support, LUKS dm-crypt modules, keyboard backlight on initrd, IOMMU - Kernel hardening: sysctl security settings (restrict BPF, perf events, ICMP redirects, source routing, suid dumps, etc.) - Locale: Europe/Paris timezone, en*US locale with fr_FR LC* settings, French keyboard layout - Audio: PipeWire with ALSA and PulseAudio compatibility (PulseAudio disabled) - Hardware: firmware, Intel/AMD CPU microcode, Bluetooth (bluez), uinput - Security: rtkit, polkit, U2F PAM (login + sudo), passwordless sudo for wheel - XDG portals: wlr portal enabled for Wayland screen sharing - Nix daemon: lix package, weekly GC (7d retention), store optimisation at 03:45, nix-command + flakes features, custom S3 binary cache, OOM-managed nix-daemon slice - Display: xserver disabled (Wayland-only), fonts dir enabled - Env: NIXOS_OZONE_WL=1, NIXPKGS_ALLOW_UNFREE=1 - System state version: 24.05

---

## firewall

### `customNixOSModules.firewall.allowedTCPPorts`

- **Type:** `list of 16 bit unsigned integer; between 0 and 65535 (both inclusive)`
- **Default:** `[]`

List of TCP port numbers to allow inbound through the firewall. Example: [ 22 80 443 ]

### `customNixOSModules.firewall.allowedUDPPorts`

- **Type:** `list of 16 bit unsigned integer; between 0 and 65535 (both inclusive)`
- **Default:** `[]`

List of UDP port numbers to allow inbound through the firewall. Example: [ 51820 ] # WireGuard

### `customNixOSModules.firewall.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable the NixOS stateful firewall (nftables/iptables). Configures a deny-by-default inbound policy: all incoming connections are silently dropped (rejectPackets = false) unless explicitly listed in allowedTCPPorts or allowedUDPPorts. Refused connection attempts are logged to the journal (logRefusedConnections = true). Dropping rather than rejecting packets avoids leaking network topology to external scanners. Outbound traffic is unrestricted. Disabled by default — enable per-machine in profiles/{hostname}/configuration.nix and set the port lists as needed.

---

## getRevision

### `customNixOSModules.getRevision.enable`

- **Type:** `boolean`
- **Default:** `true`

Whether to embed git metadata about the applied configuration into the system. At build time, reads the local .git directory (if present) and writes a JSON file to /etc/nixos/version containing: - url: the git remote URL (from .git/config) - branch: the checked-out branch (from .git/HEAD) - rev: the full commit SHA (via builtins.fetchGit) - lastModifiedDate: the commit timestamp This allows runtime inspection of exactly which nixbook commit is running, e.g. via: jq . /etc/nixos/version Also consumed by the osupdate script to show the "last applied revision" before pulling a new one. Enabled by default on all machines.

---

## greetd

### `customNixOSModules.greetd.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable the greetd display manager with tuigreet. Configures greetd to launch tuigreet, a TUI-based greeter that: - Displays a clock and remembers the last session and user - Shows an asterisk-masked password field - Presents a user menu for multi-user machines - Dynamically builds --sessions from whichever Wayland compositors are enabled (niri, sway, hyprland), so only installed sessions appear - Wraps niri sessions via niri-session for proper environment setup - Enables U2F authentication in the greetd PAM service (YubiKey login) Depends on at least one compositor module being enabled (customNixOSModules.niri, .sway, or .hyprland).

---

## hyprland

### `customNixOSModules.hyprland.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable the Hyprland dynamic tiling Wayland compositor. Hyprland is a highly customisable compositor featuring animations, blur, rounded corners, and rich IPC. This module: - Enables programs.hyprland with wlr XDG desktop portal for screen sharing - Adds U2F PAM authentication support for hyprlock (screen locker) - Registers the hyprland.cachix.org binary cache for fast builds Used on: totoro (fallback), nishinoya (fallback). See also: homeManagerModules/hyprland/ for per-user compositor configuration.

---

## laptopProfile

### `customNixOSModules.laptopProfile.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable laptop-specific power and display optimisations. Configures: - logind lid-switch behaviour: suspend on close, lock when on external power, ignore when docked - power-profiles-daemon: dynamic CPU frequency scaling (performance / balanced / power-saver profiles, switchable via e.g. the DMS control centre) - thermald: Intel thermal management daemon to prevent CPU throttling - powerManagement: general power management framework - powertop: power consumption analyser available in the system PATH Enable this on machines that are laptops (totoro, nishinoya). Leave disabled on desktop/server machines (anya).

---

## netbird-tools

### `customNixOSModules.netbird-tools.enable`

- **Type:** `boolean`
- **Default:** `true`

Whether to enable NetBird VPN client with the nswitch helper. NetBird is a WireGuard-based overlay network tool for connecting machines across different networks without port-forwarding or static IPs. This module: - Enables services.netbird (daemon only, no systray UI) - Installs nswitch: an fzf-based TUI that lists available NetBird network IDs (via `netbird networks list`) and switches to the selected one with `netbird network select && netbird up` Enabled by default on all machines.

---

## niri

### `customNixOSModules.niri.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable the Niri scrollable-tiling Wayland compositor. Niri is a modern Wayland compositor where windows are arranged in an infinite horizontal scrollable strip rather than traditional workspaces. This module: - Imports the niri-flake NixOS module (sourced from npins, not nixpkgs) - Enables programs.niri with the nixpkgs niri package - Disables the niri-flake bundled polkit agent (the system polkit handles it) - Enables GNOME keyring unlock via SDDM PAM integration - Installs essential Wayland utilities: fuzzel (launcher), grimblast (screenshots), wl-clipboard, wlr-randr (display management), libnotify, xwayland-satellite (X11 app compatibility layer) - Adds the niri.cachix.org binary cache for fast pre-built niri packages Used on: totoro (primary), nishinoya (primary). See also: homeManagerModules/niri/ for per-user compositor configuration.

---

## printTools

### `customNixOSModules.printTools.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable printing and scanning support. Configures a full CUPS + SANE stack for local and network printers/scanners: - CUPS printing daemon (services.printing) - ipp-usb: IPP-over-USB daemon for driverless USB printer/scanner access - Avahi mDNS/DNS-SD (with nssmdns4) for auto-discovery of network printers - SANE scanner framework with the airscan backend for WiFi/IPP scanners - gnome.simple-scan: GTK scanning GUI Enable on machines that have a physical printer or scanner attached, or that need to discover network printers via mDNS.

---

## sunshine

### `customNixOSModules.sunshine.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable the Sunshine game-streaming / remote-desktop server. Sunshine is an open-source implementation of the NVIDIA GameStream protocol, compatible with Moonlight clients on any device. This module: - Runs sunshine as a user systemd service tied to the graphical session target (starts/stops with the desktop session, restarts on crash) - Wraps the sunshine binary with cap_sys_admin capability so it can capture the display and audio without running as root - The web UI is available at https://localhost:47990 after first launch to pair with Moonlight clients Used on: anya (gaming/streaming machine).

---

## sway

### `customNixOSModules.sway.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable the Sway i3-compatible tiling Wayland compositor. Sway is a drop-in Wayland replacement for the i3 X11 window manager, using the same configuration syntax and keyboard-driven workflow. This module uses the SwayFX fork (programs.sway.package = pkgs.swayfx) which adds visual effects (blur, rounded corners, shadows) on top of vanilla Sway while remaining fully compatible with standard sway configs. Used on: anya (primary). See also: homeManagerModules/sway/ for per-user compositor configuration.

---

## tailscale

### `customNixOSModules.tailscale.enable`

- **Type:** `boolean`
- **Default:** `true`

Whether to enable Tailscale VPN with route-conflict workarounds. Tailscale is a mesh VPN built on WireGuard. When multiple Tailnets are configured, subnet routes can conflict with the host's default gateway, breaking connectivity. This module works around that by: - tailscale-fix-routes service: a persistent systemd unit that monitors the kernel route table via `ip monitor route` and removes conflicting /16 and /24 Tailscale subnet routes from routing table 52 as soon as they appear - tswitch (fzf-based TUI): interactive CLI tool to list and switch between Tailnets using `tailscale switch`, surfaced via fzf for fuzzy selection - Installs the tailscale package and enables services.tailscale Enabled by default on all machines.

---

## tools

### `customNixOSModules.tools.enable`

- **Type:** `boolean`
- **Default:** `true`

Whether to enable the tools NixOS module. Provides system-level tooling and services: - Container runtime: Podman with Docker compatibility alias, DNS-enabled default network, weekly auto-prune, and OCI container backend - Kernel modules: netfilter (iptables/ip6tables, conntrack, ipvs) for container networking - System packages: openvpn, gnupg, yubikey tools (yubico-piv-tool, yubioath-flutter, yubikey-personalization), podman/podman-compose, wlsunset, cups-pk-helper, ginx, osupdate, ds4drv, efibootmgr, colmena, update-systemd-resolved, pinentry-qt, lsof - YubiKey: udev rules, yubikey-touch-detector, GnuPG agent with SSH support - DS4 controller: user systemd service running ds4drv in HID-raw + xpad emulation mode for DualShock 4 controllers - osupdate: shell script that applies the latest nixbook main branch via ginx + colmena apply-local - udev: game-devices rules and uinput (MODE=0666) for unprivileged input access Note: User-level packages belong in homeManagerModules (devTools, cliTools, etc.).

---

## vmSupport

### `customNixOSModules.vmSupport.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable VirtIO paravirtual driver support in the initrd. Adds the following kernel modules to boot.initrd.availableKernelModules so the system can boot inside a QEMU/KVM or other virtio-based hypervisor: - virtio_pci — VirtIO PCI bus driver - virtio_blk — VirtIO block device (virtual disk) - virtio_scsi — VirtIO SCSI host controller - virtio_net — VirtIO network interface Enable this when building a VM image (e.g. via nixos-generators) or when testing the configuration with `test-iso` in QEMU. Not needed on bare-metal.

---

# Home Manager Modules (`customHomeManagerModules`)

## atuinConfig

### `customHomeManagerModules.atuinConfig.didactiklabs.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable Atuin shell history sync against the DidactikLabs server. Atuin replaces the standard shell history with a searchable, syncable SQLite database. The base atuin program is always enabled via commonShellConfig; this option additionally configures: - sync_address: https://atuin.didactik.labs (private DidactikLabs instance) - enter_accept: pressing Enter on a selected history item runs it immediately - sync.records: enables the newer record-based sync protocol Enable this on machines that belong to the DidactikLabs environment and where you want cross-machine shell history synchronisation. Requires the Atuin account to be set up via `atuin register` / `atuin login`.

---

## cliTools

### `customHomeManagerModules.cliTools.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable essential CLI utilities for day-to-day shell work. Installs lightweight, focused command-line tools: - jq — JSON processor / query language - yq-go — YAML/TOML/XML processor (jq-compatible syntax) - unzip — ZIP archive extraction - wget — HTTP/FTP file downloader - dig — DNS query tool (from bind-tools) - tree — Recursive directory listing This module is intentionally minimal: container-inspection tools (dive, skopeo) live in kubeTools, and richer shell integrations live in zshConfig / commonShellConfig.

---

## desktopApps

### `customHomeManagerModules.desktopApps.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable a curated set of GUI desktop applications. Installs and configures: Documents / media viewers: - zathura — lightweight keyboard-driven PDF viewer - imv — minimal Wayland image viewer (set as default for images) Communication & entertainment: - vesktop — custom Discord client (Vencord-patched) - spotify — music streaming client Creation & recording: - obs-studio — screen/audio recording and streaming - pinta — simple Paint-like image editor Display management: - wdisplays — Wayland display arrangement GUI (arandr equivalent) Browser: - firefox — set as default for http/https/text/html MIME types File management (dolphinConfig.nix, active when this is enabled): - dolphin + dolphin-plugins, ark, kio-admin, ffmpegthumbs, kpeople, kservice, ntfs3g, gparted Media playback (mpvConfig.nix, active when this is enabled): - mpv with thumbfast, mpris, and modernx scripts - yt-dlp (YouTube/media downloader) - ytui (YouTube TUI), jtui (JSON viewer TUI)

---

## devTools

### `customHomeManagerModules.devTools.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable a curated set of development and DevOps tools. Installs: Language runtimes: - python3 Build / Nix tooling: - gnumake, devenv, nix-eval-jobs, nixos-generators Infrastructure-as-Code / deployment: - terraform, minio-client - google-cloud-sdk (with gke-gcloud-auth-plugin for GKE access) Code generation / API: - cobra-cli — Go CLI framework scaffolding - openapi-generator-cli — OpenAPI client/server generator - templ — Go HTML templating compiler - bruno / bruno-cli — open-source API client (Postman alternative) AI assistants: - gemini-cli — Google Gemini CLI - claude-code — Anthropic Claude Code CLI Developer utilities: - devbox — portable development environments via Nix - go-task — Makefile alternative (Taskfile) - runme — runnable Markdown notebooks - npins — Nix dependency pinning tool

---

## dmsConfig

### `customHomeManagerModules.dmsConfig.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable DankMaterialShell (DMS) desktop shell. DMS is a Quickshell-based desktop shell providing a customisable top bar and optional dock. It is compositor-agnostic (works with niri, sway, hyprland) and integrates deeply with the rest of this configuration. Features enabled: - System monitoring widgets powered by dgop - Dynamic wallpaper-based theming via matugen (scheme-vibrant) - Audio wavelength visualiser via cava - Calendar event integration via khal - Systemd user service with auto-restart on config change Bar layout (single "Main Bar" on all screens): Left: launcherButton, nixosUpdate, workspaceSwitcher, focusedWindow, idleInhibitor Centre: music, clock, weather, opencodeUsage Right: systemTray, vpnStatus, cpuUsage, notificationButton, dankKDEConnect, battery, controlCenterButton, powerMenuButton, sathiAi Plugins bundled: - dankBatteryAlerts — low battery notifications - dankGifSearch — GIF search widget - dankStickerSearch — sticker search widget - dankKDEConnect — KDE Connect integration (auto-enabled with kdeconnect) - vpnStatus — Tailscale/NetBird VPN indicator (custom, from assets/) - sathiAi — AI assistant widget - opencodeUsage — OpenCode token usage display (when opencodeConfig enabled) - nixosUpdate — NixOS update trigger widget (calls osupdate via systemd) Also registers a nixos-upgrade-manual systemd oneshot service used by the nixosUpdate bar widget to apply system updates without a terminal. When dmsConfig is enabled, stylixConfig forces the tomorrow-night base16 scheme for colour consistency.

### `customHomeManagerModules.dmsConfig.showDock`

- **Type:** `boolean`
- **Default:** `false`

Whether to show the application dock below the bar. When true, a dock with running/pinned application icons appears at the bottom of the screen. Dock appearance is controlled by the dockTransparency, dockBottomGap, dockMargin, dockIconSize, and dockIndicatorStyle settings.

---

## fastfetchConfig

### `customHomeManagerModules.fastfetchConfig.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable Fastfetch system information display. Fastfetch is a neofetch-style system info tool written in C, significantly faster and more accurate than neofetch. This configuration: - Deploys a custom ~/.config/fastfetch/config.jsonc with a boxed layout: ┏━━━━━━━━━━━━━━━━┓ OS, Kernel, Packages, WM, Terminal, Shell ┣━━━━━━━━━━━━━━━━┫ Host, CPU, GPU, Memory, Disk ┗━━━━━━━━━━━━━━━━┛ - Deploys a custom ASCII-art NixOS snowflake logo to ~/.config/fastfetch/logo - Installs fastfetch and imagemagick (for image logo rendering) - Adds shell aliases: `fastfetch` (prepends a blank line) and `neofetch` → `fastfetch` (drop-in replacement)

---

## fcitx5Config

### `customHomeManagerModules.fcitx5Config.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable Fcitx5 input method framework with Japanese support. Fcitx5 is a modern input method framework for CJK (Chinese, Japanese, Korean) and other complex scripts on Linux. This configuration: - Input method type: fcitx5 with Wayland frontend - Addons: fcitx5-mozc-ut (Japanese IME with extended dictionary), fcitx5-gtk (GTK integration for application compatibility) - Input group "Default": Item 0: keyboard-us (English/US layout, default) Item 1: mozc (Japanese input, toggled via Ctrl+Space) Environment variables set: - QT_IM_MODULE=fcitx — Qt application input method - XMODIFIERS=@im=fcitx — X11 input method (for XWayland apps) - INPUT_METHOD=fcitx — generic fallback Used on: totoro, nishinoya (machines with Japanese input needs).

---

## fontConfig

### `customHomeManagerModules.fontConfig.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable font installation and fontconfig defaults. Installs a curated set of fonts and sets system-wide defaults: Default font families (fontconfig): - Monospace: Roboto Mono - Sans-serif: Roboto - Serif: Roboto Serif - Emoji: Noto Color Emoji Nerd Fonts (patched with icons for terminal use): - FiraCode Nerd Font - Hack Nerd Font - Iosevka Nerd Font - JetBrains Mono Nerd Font Regular fonts: - Inter — clean sans-serif UI font - Roboto / Roboto Mono / Roboto Serif — primary font family - Material Design Icons — icon font used by DMS and other widgets - Font Awesome — icon font used by various bars and prompts Enables fonts.fontconfig so the user-level fontconfig cache is managed by Home Manager.

---

## gitConfig

### `customHomeManagerModules.gitConfig.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable Git configuration and related tooling. Configures: Core git (programs.git): - gitFull package with LFS enabled - GPG signing available but off by default (signByDefault = false) - pull.rebase = true, push.autoSetupRemote = true - defaultBranch = "main", remote.prune = true - .vscode and .direnv added to global ignores - Aliases: lg (graph log), d (diff), s (status), sw/swcr (switch), save (add+commit), undo (reset HEAD~1), lazy (add+commit+push), pushmr (branch+commit+push MR), purge (delete merged branches) Difftastic (programs.difftastic): - Structural diff tool that understands syntax, used as git's diff driver GitHub CLI (programs.gh): - Extensions: gh-eco, gh-notify, gh-poi, gh-f gh-dash (programs.gh-dash): - TUI GitHub dashboard with pre-configured PR/issue sections: DidactikLabs org PRs, My PRs, Needs Review, Participating Extra packages: - tig — ncurses git history browser - git-extras — collection of git utility scripts - difftastic — also available as a standalone binary

---

## gojiConfig

### `customHomeManagerModules.gojiConfig.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable Goji conventional-commit tooling with AI assistance. Goji is a TUI/CLI tool for writing Conventional Commits with emoji. This module installs two tools: goji — interactive commit helper that prompts for type, scope, and subject, then formats the message as: <emoji> <type>(<scope>): <subject> Supported types: feat, fix, docs, refactor, chore, test, hotfix, deprecate, perf, wip, package (configured via ~/.goji.json) goji-ai — AI-powered wrapper that: 1. Runs `git diff --cached` to collect staged changes 2. Sends the diff to opencode (must be installed + authenticated) 3. Parses the JSON response to extract type/scope/subject 4. Invokes goji with the generated values Supports -t/--type, -s/--scope, -a/--add, --amend flags Requires opencode to be configured (opencodeConfig.enable = true) Also installs Zsh completion for goji (`source <(goji completion zsh)`) and Fish completion when fishConfig is enabled. Shell aliases (from commonShellConfig): gfix, gfeat, gchore. Used on: totoro, nishinoya.

---

## gtkConfig

### `customHomeManagerModules.gtkConfig.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable GTK appearance and theming configuration. Configures a consistent dark GTK theme across GTK2, GTK3, and GTK4: - Icon theme: Papirus-Dark - Cursor theme: Numix-Cursor (size 10) - Prefer dark theme flag set for all GTK versions - Font rendering: antialias + light hinting, RGB subpixel - Toolbar: BOTH_HORIZ style, LARGE_TOOLBAR icon size - GTK modules: gail and atk-bridge (accessibility) Installed theme packages: - numix-gtk-theme — Numix GTK2/3 theme - papirus-icon-theme — Papirus SVG icon set - material-design-icons — Material Design icon font - numix-icon-theme-square — Square variant of Numix icons - numix-cursor-theme — Numix cursor set - dconf — GNOME settings daemon CLI Note: Stylix (stylixConfig) overrides some GTK colours at the system level; this module controls layout/UX preferences that Stylix does not manage.

---

## hyprlandConfig

### `customHomeManagerModules.hyprlandConfig.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable per-user Hyprland compositor configuration. Manages the full Hyprland user environment via Home Manager: - hyprlandConfig.nix: wayland.windowManager.hyprland settings — keybindings, animations, decorations, workspace rules, monitor layout, exec-once startup commands, environment variables, and input device configuration - hyprlockConfig.nix: hyprlock screen-locker configuration — background blur, clock widget, password input field styling Requires the system-level nixosModules/hyprland.nix to be enabled (customNixOSModules.hyprland.enable = true). Used on: totoro (fallback), nishinoya (fallback).

---

## kittyConfig

### `customHomeManagerModules.kittyConfig.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable Kitty terminal emulator configuration. Kitty is a GPU-accelerated terminal emulator with tiling support. Configures: Appearance & behaviour: - Roboto Mono 10pt font, copy-on-select, no OS window close prompt - Cursor blink interval 0.5s, cursor trail effect with smooth decay - Bottom powerline tab bar (shown even for a single tab) - Splits layout only (kitty's built-in window splitting, no tmux needed) Keybindings: - Ctrl+Shift+S / Ctrl+Shift+Enter — vertical / horizontal split - Ctrl+Shift+W — close tab; Ctrl+Shift+←/→ — previous/next tab - Alt+←/→/↑/↓ — navigate between splits - Shift+←/→/↑/↓ — move/reorder splits Compositor integration (spawn kitty on Mod+Return): - Hyprland: $mod+RETURN keybind - Niri: Mod+Return bind - Sway: terminal = kitty, Mod4+Return keybind Shell integration: - Zsh integration enabled inside kitty - `ssh` aliased to TERM=xterm-256color inside kitty (fixes remote terms) - `sshs` alias uses kitty+kitten ssh for seamless remote kitty sessions VSCode integration: - Sets kitty as the external terminal (terminal.external.linuxExec) ranger: - Configures image previews via the kitty graphics protocol

---

## kubeConfig

### `customHomeManagerModules.kubeConfig.bealv.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to deploy the Bealv OIDC kubeconfigs (prod + non-prod). Copies two kubeconfigs to ~/.kube/configs/bealv/: - oidc@bealv.kubeconfig (non-production cluster) - oidc@bealvprod.kubeconfig (production cluster)

### `customHomeManagerModules.kubeConfig.didactiklabs.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to deploy the DidactikLabs OIDC kubeconfig. Copies assets/kubeconfigs/oidc-didactiklabs.kubeconfig to ~/.kube/configs/didactiklabs/oidc@didactiklabs.kubeconfig so kubeswitch can discover it automatically.

### `customHomeManagerModules.kubeConfig.logicmg.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to deploy the LogicMG OIDC kubeconfig. Copies assets/kubeconfigs/oidc-logicmg.kubeconfig to ~/.kube/configs/logicmg/oidc@logicmg.kubeconfig. Used on: nishinoya (aamoyel's machine).

---

## kubeTools

### `customHomeManagerModules.kubeTools.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable the full Kubernetes toolchain. Installs a comprehensive set of Kubernetes CLI tools and utilities: Core: - kubectl — Kubernetes CLI - kubernetes-helm — Helm package manager - k9s — TUI cluster dashboard (config in k9sConfig.nix) - kubeswitch — multi-kubeconfig context switcher (kswitch alias) - kubelogin-oidc — OIDC authentication plugin for kubectl - kustomize — Kubernetes overlay management Inspection & debugging: - kubectl-neat — strip noisy fields from kubectl YAML output - kubectl-view-secret — base64-decode secrets in-place - kubectl-explore — interactive resource browser - skopeo — inspect/copy container images without pulling - dive — explore container image layers - netfetch — network debugging tool - kubevirt — virtctl for KubeVirt VMs (SSH, console) - fluxcd — Flux GitOps CLI (flux) Custom packages: - kl — opinionated multi-pod log viewer - songbird — custom cluster management utility - pvmigrate — Proxmox VM migration tool - crd-wizard — CRD visualisation dashboard (Shift-E in k9s) - sou — container image analysis wrapper Others: - kubebuilder — Kubernetes controller scaffolding - kind — local Kubernetes clusters via Docker - paralus-cli — Paralus zero-trust access CLI Also sets: - k=kubectl shell alias - pctl=cli shell alias - kubectl and songbird Zsh completions See also: kubeConfig.\* options for OIDC kubeconfig file deployment, and k9sConfig.nix for k9s settings and plugins.

---

## kubeswitchConfig

### `customHomeManagerModules.kubeswitchConfig.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable kubeswitch context-switcher configuration. kubeswitch (exposed as the `kswitch` command) is a terminal UI and CLI for switching between multiple kubeconfigs / contexts stored across many files. This replaces the traditional KUBECONFIG env-var juggling. Configuration: - commandName: kswitch (aliased as `ks` in the shell) - Zsh integration enabled (shell function injection) - Fish integration enabled when fishConfig is active - Store: filesystem, scanning ~/.kube/configs/\*_ for files matching _._ (picks up all kubeconfigs deployed by the kubeConfig._.enable options) - Kind: SwitchConfig v1alpha1 Requires kubeTools.enable = true to have the kubeswitch binary available. Used on: totoro, nishinoya.

---

## niriConfig

### `customHomeManagerModules.niriConfig.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable per-user Niri compositor configuration. Manages the full Niri scrollable-tiling user environment via Home Manager: - niriConfig.nix: programs.niri.settings — keybindings, window rules, output/monitor configuration (via kanshi-style prefer-output rules), input device settings, animations, environment variables, spawn-at-startup commands, and workspace configuration Niri arranges windows in an infinite horizontal scrollable strip. Key concepts: columns (vertical stacks), workspaces (virtual desktops), and outputs (physical monitors). Requires the system-level nixosModules/niri.nix to be enabled (customNixOSModules.niri.enable = true). Used on: totoro (primary), nishinoya (primary).

---

## nixvimConfig

### `customHomeManagerModules.nixvimConfig.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable NixVim — a fully declarative Neovim configuration. NixVim manages Neovim and all its plugins through the Nix module system, ensuring reproducibility. This configuration sets up a complete IDE-like environment: Core settings (options.nix): - Space as leader/localleader key - System clipboard via wl-copy (Wayland) - Relative + absolute line numbers, scrolloff=8, cursorline/column - Undo history persistence, incremental search, smart case - 4-space tabs with auto-indent, no swap file - Disabled providers: ruby, perl, python2 Plugins (plugins/): LSP & completion: lsp (gopls, nil, ts-ls, pylsp, lua-ls…), cmp (nvim-cmp with LSP/buffer/path sources), none-ls (formatters/linters) Navigation: telescope (fuzzy finder), neo-tree (file explorer), trouble (diagnostics list) Editing: comment, mini (surround, pairs, etc.), git-conflict, trim, vim-better-whitespace UI: barbar (tabline), lualine (statusline), noice (cmdline/messages UI), notify, snacks, smear-cursor, neoscroll, colorizer, markdown-preview, floaterm, startify Extras: neocord (Discord Rich Presence), treesitter (syntax highlighting), opencode (AI coding assistant integration), 99 (custom utility plugin) French spell-check files (fr.utf-8 + fr.latin1) are pre-fetched and deployed to ~/.config/nvim/spell/. Keybindings: <leader>a (code action), Shift-H/L (prev/next buffer), Ctrl-L (clear highlight), Ctrl-Shift-arrows (resize splits). vi/vim aliases enabled, set as default editor.

---

## opencodeConfig

### `customHomeManagerModules.opencodeConfig.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable OpenCode AI coding assistant configuration. OpenCode is an AI-powered terminal coding assistant that supports multiple LLM providers through a plugin system. This configuration enables programs.opencode with two authentication plugins: - opencode-gemini-auth — Google Gemini OAuth authentication - opencode-anthropic-oauth — Anthropic Claude OAuth authentication When enabled, other modules integrate with OpenCode: - rtkConfig: runs `rtk init -g --opencode` to wire up the RTK auto-rewrite hook for token optimisation - goji.nix: goji-ai uses `opencode run` to generate commit messages - dmsConfig: the opencodeUsage bar widget shows token consumption Requires `opencode auth login` after activation to authenticate with a provider.

---

## rtk

### `customHomeManagerModules.rtk.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable RTK (Rust Token Killer). RTK is a CLI proxy that transparently intercepts common development commands (git, kubectl, terraform, etc.) and compresses / summarises their output before passing it to an LLM, reducing token consumption by 60–90% on typical dev workflows. This module: - Installs the rtk binary (custom package from customPkgs/rtk.nix) - Runs `rtk init --global` on Home Manager activation to register rtk's shell hooks globally (~/.config/rtk/) - When opencodeConfig is enabled, runs `rtk init -g --opencode` instead, which also wires up the opencode auto-rewrite hook so that rtk automatically rewrites commands piped through opencode Used on: totoro.

---

## sshConfig

### `customHomeManagerModules.sshConfig.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable SSH client configuration. Configures programs.ssh with sensible keep-alive defaults applied to all hosts (Match \*): - compression: false — disabled to reduce CPU overhead on fast links - serverAliveInterval: 10s — send a keep-alive every 10 seconds - serverAliveCountMax: 2 — disconnect after 2 missed keep-alives (20s) enableDefaultConfig = false so NixOS's generated defaults do not conflict with this configuration. SSH keys are managed separately via agenix secrets. The GnuPG agent SSH socket (YubiKey SSH) is configured at the system level in nixosModules/tools.nix.

---

## starship

### `customHomeManagerModules.starship.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable the Starship cross-shell prompt. Starship is a fast, minimal, and infinitely customisable prompt written in Rust. This configuration uses a two-line layout with Stylix colour integration (base16 palette pulled from config.lib.stylix.colors): Top line: [nix_shell] user@hostname [k8s context] in path git_branch [status] Bottom line: ❯ (green on success, red on error, ❮ in vi-mode) Enabled modules: - nix_shell — shows "pure"/"impure" when inside a nix shell/develop env - username — always visible (not just on SSH) - hostname — always visible, trimmed at first dot - kubernetes — ☸ symbol + current context (never disabled) - directory — path truncated to 4 segments with …/ symbol, 🔒 for read-only - git_branch — symbol + branch name - git_status — ⇡⇣⇕ ahead/behind/diverged, +!?✘»$ staged/modified/untracked/etc. Disabled modules (for prompt speed): time, package, python, git_metrics. Zsh integration enabled.

---

## stylixConfig

### `customHomeManagerModules.stylixConfig.enable`

- **Type:** `boolean`
- **Default:** `true`

Whether to enable Stylix declarative theming. Stylix generates a consistent base16 colour palette from the wallpaper image and applies it automatically to supported applications (terminals, editors, bars, GTK, etc.). This configuration: - polarity: dark — always generates a dark colour scheme - image: pulled from profileCustomization.mainWallpaper (set per profile) - autoEnable: true — opt-in theming for all supported Stylix targets - Disabled targets: dank-material-shell — DMS manages its own theming via matugen k9s — Stylix's k9s target causes schema errors - Cursor: phinger-cursors-light, size 24 Fonts (shared with fontConfig): - Monospace: Roboto Mono - Sans-serif: Roboto - Serif: Roboto Serif DMS override: when dmsConfig is enabled, forces the base16 scheme to tomorrow-night.yaml (from base16-schemes) instead of the wallpaper- derived palette, keeping DMS colours consistent. Enabled by default — disable only if you want fully manual theming.

---

## swayConfig

### `customHomeManagerModules.swayConfig.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable per-user Sway compositor configuration. Manages the full Sway i3-compatible tiling environment via Home Manager: - swayConfig.nix: wayland.windowManager.sway.config — keybindings, workspace layout, bar configuration, input device settings, output configuration, exec-on-startup commands, gaps, borders, and Sway-specific SwayFX visual effects (blur, corner radius) References: https://arewewaylandyet.com/ https://github.com/swaywm/sway/wiki/Useful-add-ons-for-sway Requires the system-level nixosModules/sway.nix to be enabled (customNixOSModules.sway.enable = true). Used on: anya (primary).

---

## thunderbirdConfig

### `customHomeManagerModules.thunderbirdConfig.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable Mozilla Thunderbird email client. Installs and manages the Thunderbird email/calendar client via Home Manager's programs.thunderbird module. Account configuration and profiles are managed manually through the Thunderbird UI (not declaratively, as mail credentials are sensitive). Used on: totoro, nishinoya.

---

## volumeScript

### `customHomeManagerModules.volumeScript.enable`

- **Type:** `boolean`
- **Default:** `true`

Whether to enable the volume control script and media-key keybindings. Installs the `volume` shell script (originally by JaKooLit), a PipeWire/ pamixer-based volume manager that: - --inc / --dec : raise/lower default sink volume by 5%, capped at 100% - --toggle : toggle mute on the default sink - --toggle-mic : toggle mute on the default source (microphone) - --get-icon : print the appropriate volume icon name for notifications - --notify : send a libnotify desktop notification with current volume and icon (reads icon images from ~/.config/assets/images/volume-icons/) (no args) : print volume and send notification Compositor keybinding integration: - When dmsConfig is disabled: binds XF86AudioRaiseVolume/LowerVolume/Mute to the volume script for Hyprland (bindle) and Sway (keybindings) - When dmsConfig is enabled: uses wpctl directly (WirePlumber CLI) for raise/lower (+/-3%), keeping volume changes fast and DMS OSD-aware; mute still uses the volume script for the toggle notification Enabled by default.

---

## vscode

### `customHomeManagerModules.vscode.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable Visual Studio Code with a declarative extension set. Manages VSCode entirely through Home Manager (mutableExtensionsDir = false), ensuring the extension list is reproducible and version-pinned. Extensions (200+, defined in extensionsList.nix): Languages: Go, Rust, Python (Pylance + pylint + black), TypeScript, Nix, Ansible, Terraform/OpenTofu, YAML, TOML, Markdown, Docker, Kubernetes, Helm, SQL, Java, C/C++, HTML/CSS AI assistants: GitHub Copilot (inline + chat), Continue Git: GitLens, Git Graph, GitHub Pull Requests Formatting: Prettier, EditorConfig, run-on-save (golines for Go, nixfmt for Nix files) UI/UX: Material Theme, Material Icons, indent-rainbow, Error Lens, Project Manager, Todo Tree User settings (profiles.default.userSettings): - Go: golines formatter (max line length 140) on save - Nix: nixfmt on save via emeraldwalk.runonsave - Python: Pylance language server, pylint linter, black formatter - Ansible: full OIDC collection names, lint enabled - GitHub Copilot: inline suggestions (3), completions (10) - kitty integration: sets kitty as external terminal Extra packages installed alongside VSCode: - exercism — coding challenge CLI - golines — Go line-length formatter - nixfmt — Nix code formatter Used on: nishinoya.

---

## zshConfig

### `customHomeManagerModules.zshConfig.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable Zsh with full shell integrations and common tooling. Enables programs.zsh with: - oh-my-zsh framework - zsh-syntax-highlighting plugin (v0.8.0) — real-time command colouring - zsh-bat plugin — replaces `cat` output with bat syntax highlighting - Autosuggestions (fish-style inline suggestions) - any-nix-shell integration: preserves the Zsh shell inside `nix shell` and `nix develop` environments instead of dropping to bash Shell integrations (from commonShellConfig): - atuin — shell history search/sync (up-arrow disabled, manual Ctrl-R) - yazi — terminal file manager (y alias) - zoxide — smarter `cd` replacement (cd aliased to `z`) - fzf — fuzzy finder with tmux integration - eza — modern `ls` replacement - direnv — per-directory environment loading (nix-direnv enabled) Common packages installed: ginx, trippy, any-nix-shell, duf, sd, viddy, witr, dgop, devenv (see commonShellConfig.nix for the full list). Common aliases: ks=kswitch, watch=viddy, y=yazi, top=dgop, df=duf, cd=z, neofetch=fastfetch, gfix/gfeat/gchore (goji shortcuts).
