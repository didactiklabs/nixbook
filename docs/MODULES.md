# Nixbook Custom Module Options

> **Auto-generated** from the Nix module definitions.
> Run `nix-build docs/generate-docs.nix && cp result/MODULES.md docs/MODULES.md` to regenerate.

## Table of Contents

### NixOS Modules

- [caCertificates](#cacertificates)
- [core](#core)
- [fcitx5-lotus](#fcitx5-lotus)
- [firewall](#firewall)
- [gamingConfig](#gamingconfig)
- [getRevision](#getrevision)
- [greetd](#greetd)
- [hyprland](#hyprland)
- [lanzaboote](#lanzaboote)
- [laptopProfile](#laptopprofile)
- [netbird-tools](#netbird-tools)
- [niri](#niri)
- [ollama](#ollama)
- [printTools](#printtools)
- [simracing](#simracing)
- [sunshine](#sunshine)
- [sway](#sway)
- [tailscale](#tailscale)
- [tools](#tools)
- [vmSupport](#vmsupport)
- [wolf](#wolf)

### Home Manager Modules

- [atuinConfig](#atuinconfig)
- [cliTools](#clitools)
- [desktopApps](#desktopapps)
- [desktopEntriesConfig](#desktopentriesconfig)
- [devTools](#devtools)
- [dmsConfig](#dmsconfig)
- [fastfetchConfig](#fastfetchconfig)
- [fcitx5Config](#fcitx5config)
- [fontConfig](#fontconfig)
- [foxblatConfig](#foxblatconfig)
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
- [oversteerConfig](#oversteerconfig)
- [rbwConfig](#rbwconfig)
- [rtk](#rtk)
- [sshConfig](#sshconfig)
- [starship](#starship)
- [stylixConfig](#stylixconfig)
- [swayConfig](#swayconfig)
- [thunderbirdConfig](#thunderbirdconfig)
- [vscode](#vscode)
- [zenBrowserConfig](#zenbrowserconfig)
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

### `customNixOSModules.caCertificates.rpcu.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to install the RPCU internal CA certificate system-wide. Adds assets/certs/rpcu-ca.crt to the system PKI trust store and exposes it at /etc/ssl/certs/rpcu-ca.crt so tools like curl, git, and browsers trust internal RPCU HTTPS endpoints without warnings.

---

## core

### `customNixOSModules.core.enable`

- **Type:** `boolean`
- **Default:** `true`

Whether to enable the core NixOS module. This is the foundational system module that configures: - Boot: systemd-boot UEFI loader, plymouth splash screen, latest kernel, LVM support, LUKS dm-crypt modules, keyboard backlight on initrd, IOMMU, NTFS + exFAT filesystem support for external drives - Kernel hardening: sysctl security settings (restrict BPF, perf events, ICMP redirects, source routing, suid dumps, etc.) - Locale: Europe/Paris timezone, en*US locale with fr_FR LC* settings, French keyboard layout - Audio: PipeWire with ALSA and PulseAudio compatibility (PulseAudio disabled) - Hardware: firmware, Intel/AMD CPU microcode, Bluetooth (bluez), uinput - Security: rtkit, polkit, U2F PAM (login + sudo), passwordless sudo for wheel - XDG portals: wlr portal enabled for Wayland screen sharing - Nix daemon: lix package, weekly GC (7d retention), store optimisation at 03:45, nix-command + flakes features, custom S3 binary cache, OOM-managed nix-daemon slice - Display: xserver disabled (Wayland-only), fonts dir enabled - Env: NIXOS_OZONE_WL=1, NIXPKGS_ALLOW_UNFREE=1 - System state version: 24.05

---

## fcitx5-lotus

### `customNixOSModules.fcitx5-lotus.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable Fcitx5 Lotus — an open-source Vietnamese input method for fcitx5. Unlike a plain fcitx5 addon, Lotus relies on a privileged uinput server that injects key events, so it needs system-level support: a udev rule granting the server access to /dev/uinput, a `uinput_proxy` system user, and a per-user `fcitx5-lotus-server@<user>.service` instance. Set `users` to the list of login users that should get a Lotus server. The Lotus fcitx5 addon is added to i18n.inputMethod.fcitx5.addons, so add "lotus" to the user's fcitx5 input-method group to use it. https://github.com/LotusInputMethod/fcitx5-lotus .

### `customNixOSModules.fcitx5-lotus.package`

- **Type:** `package`
- **Default:** `"/nix/store/xxpxdq4ma5dh626dc2f040v9cx17nyxh-fcitx5-lotus-3.5.9"`

The fcitx5-lotus package to install.

### `customNixOSModules.fcitx5-lotus.users`

- **Type:** `list of string`
- **Default:** `[]`

Login users to start a system-level fcitx5-lotus-server instance for. Each user gets one fcitx5-lotus-server@<user>.service.

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

## gamingConfig

### `customNixOSModules.gamingConfig.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable the gaming-oriented NixOS configuration. This module provides a production-grade gaming setup inspired by Jovian-NixOS (Steam Deck / SteamOS). It bundles: - Steam with remote play, Proton GE and Proton CachyOS compatibility, and extest - GameMode performance daemon - 32-bit graphics and driver support - Gamepad / controller udev rules (uinput, Valve HID devices) GPU-specific tuning (AMD kernel boot parameters and early modesetting) is gated behind the `gpu` option below, so this module is usable on both AMD and NVIDIA machines. Used on: anya (AMD gaming/streaming desktop), hanamichi (NVIDIA desktop). Reference: https://github.com/Jovian-Experiments/Jovian-NixOS

### `customNixOSModules.gamingConfig.gpu`

- **Type:** `one of "amd", "nvidia", "none"`
- **Default:** `"amd"`

Which GPU vendor the machine uses. Controls vendor-specific tuning: - "amd": applies AMD GPU kernel boot parameters (TDR timeouts, TTM page pool, scheduler submission depth, IOMMU off) and early `amdgpu` modesetting in initrd. - "nvidia": skips all AMD-specific tuning. Configure the proprietary driver (`hardware.nvidia`, `services.xserver.videoDrivers`) in the machine profile. - "none": GPU-agnostic; only the common gaming stack (Steam, GameMode, 32-bit graphics) is applied.

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

## lanzaboote

### `customNixOSModules.lanzaboote.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable lanzaboote for UEFI Secure Boot. Lanzaboote replaces systemd-boot and signs the kernel and initrd with a machine-specific key so that Secure Boot can verify them. Automatic provisioning is enabled by default: - On first boot, a systemd service generates signing keys. - Another service prepares Authenticated Variables on the ESP, re-signs all boot artifacts, and triggers a reboot. - On the next boot, systemd-boot enrolls the keys into the firmware and Secure Boot enforcement begins. This is a trust-on-first-use model: the first boot is unsigned, subsequent boots are signed and verified. After provisioning, verify with: bootctl status (should show Secure Boot: enabled) sudo sbctl verify (all boot entries should be signed) When this option is enabled: - boot.loader.systemd-boot.enable is forced to false (they are mutually exclusive). - boot.lanzaboote.enable is set to true with automatic key generation and enrollment. - The configurationLimit defaults to 10. Disable this option on machines that do not use Secure Boot.

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

Whether to enable the Niri scrollable-tiling Wayland compositor. Niri is a modern Wayland compositor where windows are arranged in an infinite horizontal scrollable strip rather than traditional workspaces. This module: - Imports the niri-flake NixOS module (sourced from npins, not nixpkgs) - Enables programs.niri with the nixpkgs niri package - Disables the niri-flake bundled polkit agent and replaces it with polkit-gnome as a systemd user service (required for privilege-escalation dialogs) - Installs essential Wayland utilities: fuzzel (launcher), grimblast (screenshots), wl-clipboard, libnotify, xwayland-satellite (X11 app compatibility layer) - Installs networkmanagerapplet (nm-applet + nm-connection-editor) for WPA Enterprise credential prompts and advanced network configuration - Adds xdg-desktop-portal-gtk for FileChooser (avoids Nautilus dependency) - Ensures the GNOME portal backend auto-starts with the session and restarts on crash - Adds the niri.cachix.org binary cache for fast pre-built niri packages Used on: totoro (primary), tanjiro (primary), nishinoya (primary). See also: homeManagerModules/niri/ for per-user compositor configuration.

---

## ollama

### `customNixOSModules.ollama.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable the Ollama local LLM inference server. Ollama is an open-source framework for running large language models locally. This module: - Runs Ollama as a systemd service (services.ollama) - Uses ROCm GPU acceleration for AMD GPUs - Preloads the Gemini Gemma 4 27B model on first start - Exposes the Ollama API at http://localhost:11434 Used on: anya (gaming/streaming desktop with AMD GPU). Reference: https://wiki.nixos.org/wiki/Ollama

---

## printTools

### `customNixOSModules.printTools.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable printing and scanning support. Configures a full CUPS + SANE stack for local and network printers/scanners: - CUPS printing daemon (services.printing) - ipp-usb: IPP-over-USB daemon for driverless USB printer/scanner access - Avahi mDNS/DNS-SD (with nssmdns4) for auto-discovery of network printers - SANE scanner framework with the airscan backend for WiFi/IPP scanners - simple-scan: GTK scanning GUI cups-browsed is explicitly disabled: modern CUPS does driverless / IPP-Everywhere discovery natively via Avahi/DNS-SD, and browsed's legacy "implicitclass://" auto-queues silently drop jobs when they can't resolve a destination host. Add discovered driverless printers directly through the CUPS web UI (http://localhost:631) instead. Enable on machines that have a physical printer or scanner attached, or that need to discover network printers via mDNS.

---

## simracing

### `customNixOSModules.simracing.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable sim racing hardware support. This module provides comprehensive configuration for direct-drive wheelbases and sim racing peripherals, targeting Moza Racing (VID 346e) and Fanatec (VID 0eb7) hardware: - Moza & Fanatec udev rules for serial (Foxblat config), HID (FFB), USB, and input device access - Foxblat — Linux Moza configuration tool (fork of boxflat, Pit House alt) - Oversteer — generic steering wheel manager (rotation, FFB gain, autocenter, combine pedals, etc.); also supports Fanatec wheels - Joystick and FFB testing utilities (evtest, fftest, jstest) - USB autosuspend disabled for Moza/Fanatec devices to prevent drops - CDC ACM kernel module for Moza serial communication The kernel PIDFF (PID Force Feedback) driver handles all FFB for Moza, Fanatec, and other direct-drive wheelbases natively since kernel 6.15+. Used on: anya (gaming/streaming desktop), hanamichi (gaming desktop). Reference: https://github.com/JacKeTUs/universal-pidff Reference: https://github.com/giantorth/foxblat (fork of Lawstorant/boxflat)

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

Whether to enable Tailscale VPN with exit node support and native nftables. Tailscale is a mesh VPN built on WireGuard. This module configures: - services.tailscale with useRoutingFeatures = "both" for full exit node and subnet router support - Native nftables backend via TS_DEBUG_FIREWALL_MODE=nftables to avoid iptables-compat translation layer issues - IP forwarding (IPv4 + IPv6) and loose reverse-path filtering for exit node traffic - Firewall: trusts the tailscale0 interface and allows the Tailscale UDP port through - tswitch (fzf-based TUI): interactive CLI tool to list and switch between Tailnets using `tailscale switch`, surfaced via fzf for fuzzy selection Enabled by default on all machines.

---

## tools

### `customNixOSModules.tools.enable`

- **Type:** `boolean`
- **Default:** `true`

Whether to enable the tools NixOS module. Provides system-level tooling and services: - Container runtime: Podman with Docker compatibility alias, DNS-enabled default network, weekly auto-prune, and OCI container backend - Kernel modules: netfilter (iptables/ip6tables, conntrack, ipvs) for container networking - System packages: openvpn, gnupg, yubikey tools (yubico-piv-tool, yubioath-flutter, yubikey-personalization), podman/podman-compose, wlsunset, cups-pk-helper, ginx, osupdate, ds4drv, efibootmgr, colmena, update-systemd-resolved, pinentry-qt, lsof - YubiKey: udev rules, yubikey-touch-detector, GnuPG agent with SSH support - FIDO2: libfido2 package and udev rules for SSH security keys (ed25519-sk/ecdsa-sk) - DS4 controller: user systemd service running ds4drv in HID-raw + xpad emulation mode for DualShock 4 controllers - osupdate: shell script that applies the latest nixbook main branch via ginx + colmena apply-local - udev: game-devices rules and uinput (MODE=0666) for unprivileged input access Note: User-level packages belong in homeManagerModules (devTools, cliTools, etc.).

---

## vmSupport

### `customNixOSModules.vmSupport.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable VirtIO paravirtual driver support in the initrd. Adds the following kernel modules to boot.initrd.availableKernelModules so the system can boot inside a QEMU/KVM or other virtio-based hypervisor: - virtio_pci — VirtIO PCI bus driver - virtio_blk — VirtIO block device (virtual disk) - virtio_scsi — VirtIO SCSI host controller - virtio_net — VirtIO network interface Enable this when building a VM image (e.g. via nixos-generators) or when testing the configuration with `test-iso` in QEMU. Not needed on bare-metal.

---

## wolf

### `customNixOSModules.wolf.den.port`

- **Type:** `16 bit unsigned integer; between 0 and 65535 (both inclusive)`
- **Default:** `8080`

The port on which wolf-den web UI listens.

### `customNixOSModules.wolf.enable`

- **Type:** `boolean`
- **Default:** `false`

whether to enable wolf globally or not

### `customNixOSModules.wolf.hostAppsStateFolder`

- **Type:** `string`
- **Default:** `"/etc/wolf"`

The path to the Wolf application state folder on the host.

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

## desktopEntriesConfig

### `customHomeManagerModules.desktopEntriesConfig.enable`

- **Type:** `boolean`
- **Default:** `true`

Whether to hide desktop launcher entries for non-user-facing utilities, settings tools, background daemons and duplicate launchers (e.g. kvantummanager, fcitx5 daemon/helpers/config GUIs, KDE Connect daemon entries, geoclue demos, pinentry, nm-connection-editor, xdg portals, khal, umpv, imv-dir, kbd-layout-viewer, quickshell, nixos-manual). Implemented via hiPrio desktop-item packages with NoDisplay=true that shadow the originals in the user profile. System-wide qt5ct/qt6ct are hidden separately in nixosModules/userConfig.nix.

---

## devTools

### `customHomeManagerModules.devTools.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable a curated set of development and DevOps tools. Installs: Language runtimes: - python3 Build / Nix tooling: - gnumake, devenv, nix-eval-jobs, nixos-generators Infrastructure-as-Code / deployment: - terraform, minio-client - google-cloud-sdk (with gke-gcloud-auth-plugin for GKE access) Code generation / API: - cobra-cli — Go CLI framework scaffolding - openapi-generator-cli — OpenAPI client/server generator - templ — Go HTML templating compiler - bruno / bruno-cli — open-source API client (Postman alternative) AI assistants: - gemini-cli — Google Gemini CLI - claude-code — Anthropic Claude Code CLI Developer utilities: - devbox — portable development environments via Nix - go-task — Makefile alternative (Taskfile) - runme — runnable Markdown notebooks - npins — Nix dependency pinning tool - openchoreo-cli — OpenChoreo internal developer platform CLI (occ)

---

## dmsConfig

### `customHomeManagerModules.dmsConfig.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable DankMaterialShell (DMS) desktop shell. DMS is a Quickshell-based desktop shell providing a customisable top bar and optional dock. It is compositor-agnostic (works with niri, sway, hyprland) and integrates deeply with the rest of this configuration. Features enabled: - System monitoring widgets powered by dgop - Dynamic wallpaper-based theming via matugen (scheme-vibrant) - Audio wavelength visualiser via cava - Calendar event integration via khal - Systemd user service with auto-restart on config change - Native low (20%) / critical (10%) battery notifications Bar layout (single "Main Bar" on all screens): Left: launcherButton, nixosUpdate, workspaceSwitcher, focusedWindow Centre: music, clock, weather, opencodeUsage, githubNotifierCustom Right: systemTray, markets, vpnStatus, cpuUsage, notificationButton, dankKDEConnect, controlCenterButton, sathiAi Plugins bundled: - markets — market ticker widget - dankGifSearch — GIF search widget - dankStickerSearch — sticker search widget - dankKDEConnect — KDE Connect integration (auto-enabled with kdeconnect) - vpnStatus — Tailscale/NetBird VPN indicator (custom, from assets/) - sathiAi — AI assistant widget - githubNotifierCustom — GitHub notification indicator (custom, from assets/) - opencodeUsage — OpenCode token usage display (when opencodeConfig enabled) - nixosUpdate — NixOS update trigger widget (calls osupdate via systemd) Also registers a nixos-upgrade-manual systemd oneshot service used by the nixosUpdate bar widget to apply system updates without a terminal. When dmsConfig is enabled, stylixConfig forces the tomorrow-night base16 scheme for colour consistency.

### `customHomeManagerModules.dmsConfig.enableDankCalendar`

- **Type:** `boolean`
- **Default:** `true`

Whether to enable DankCalendar, a standalone calendar application from the Dank Linux Suite. It supports Local, Google, Microsoft, CalDAV, and iCloud calendars with a Quickshell-based UI. When true, the dcal binary and quickshell UI are installed and a systemd user service is registered to keep the calendar daemon running in the background (sync + reminders).

### `customHomeManagerModules.dmsConfig.enableNixosUpdate`

- **Type:** `boolean`
- **Default:** `true`

Whether to enable the nixosUpdate DMS bar widget and the accompanying nixos-upgrade-manual systemd oneshot service. When true, the nixosUpdate plugin (from assets/dms/plugins/nixos-update) is loaded into the bar and a systemd user service is registered so the widget can trigger a system upgrade (via osupdate) without opening a terminal. Disable this on machines where the widget is not desired or where the osupdate script is unavailable.

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

### `customHomeManagerModules.fcitx5Config.addons`

- **Type:** `list of package`
- **Default:** `["/nix/store/psxg9jx9ynz3fwfv2c8zy9n6904yzxn2-fcitx5-mozc-2.30.5544.102","/nix/store/0n3danf5wqdlqbxh39rd7299gkmfyvv5-fcitx5-gtk-5.1.7"]`

Fcitx5 addon packages to install (IME engines and integrations). Defaults to the Japanese Mozc engine plus GTK integration.

### `customHomeManagerModules.fcitx5Config.defaultIM`

- **Type:** `string`
- **Default:** `"keyboard-us"`

Name of the input method activated by default (should be one of the entries in `inputMethods`).

### `customHomeManagerModules.fcitx5Config.defaultLayout`

- **Type:** `string`
- **Default:** `"us"`

XKB layout used as the group's default layout.

### `customHomeManagerModules.fcitx5Config.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable Fcitx5 input method framework. Fcitx5 is a modern input method framework for CJK (Chinese, Japanese, Korean), Vietnamese and other complex scripts on Linux. This configuration: - Input method type: fcitx5 with Wayland frontend - Addons and input methods are configurable via the `addons`, `inputMethods`, `defaultLayout` and `defaultIM` options below. Environment variables set: - QT_IM_MODULE=fcitx — Qt application input method - XMODIFIERS=@im=fcitx — X11 input method (for XWayland apps) - INPUT_METHOD=fcitx — generic fallback Switch input methods at runtime with Ctrl+Space. The trigger key cycles forward through all input methods in the group (not just the last two), via globalOptions.Hotkey.EnumerateWithTriggerKeys. Used on: totoro, nishinoya (Japanese), hanamichi (German + Vietnamese).

### `customHomeManagerModules.fcitx5Config.inputMethods`

- **Type:** `list of string`
- **Default:** `["keyboard-us","mozc"]`

Ordered list of fcitx5 input-method engine names making up the "Default" input group. The first entry is used as the active default. Common values: - "keyboard-us" US/English XKB layout - "keyboard-de" German XKB layout - "keyboard-fr" French XKB layout - "mozc" Japanese - "unikey" Vietnamese (Telex/VNI)

### `customHomeManagerModules.fcitx5Config.lotus`

- **Type:** `boolean`
- **Default:** `false`

Whether to add the Fcitx5 Lotus Vietnamese input method addon. When enabled, the Lotus addon is appended to `addons`; add "lotus" to `inputMethods` to put it in the switch cycle. IMPORTANT: Lotus also needs system-level support (a uinput server, udev rule and per-user service). Enable the matching NixOS module on the host: customNixOSModules.fcitx5-lotus = { enable = true; users = [ "<username>" ]; }; https://github.com/LotusInputMethod/fcitx5-lotus

### `customHomeManagerModules.fcitx5Config.schnelleUmlaute`

- **Type:** `boolean`
- **Default:** `false`

Whether to install the "Schnelle Umlaute" fcitx5 addon, which types umlauts and eszett with a hold-letter + Space gesture, Telex-style: hold a + Space → ä hold o + Space → ö hold u + Space → ü hold s + Space → ß (Shift+letter + Space → uppercase Ä/Ö/Ü) Releasing the key without Space types the normal letter, so ordinary typing is unaffected. Mappings/leader keys can be tweaked with the bundled `schnelle-umlaute-editor` GUI. https://github.com/Maik-0000FF/schnelle-umlaute

---

## fontConfig

### `customHomeManagerModules.fontConfig.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable font installation and fontconfig defaults. Installs a curated set of fonts and sets system-wide defaults: Default font families (fontconfig): - Monospace: Roboto Mono - Sans-serif: Roboto - Serif: Roboto Serif - Emoji: Noto Color Emoji Nerd Fonts (patched with icons for terminal use): - FiraCode Nerd Font - Hack Nerd Font - Iosevka Nerd Font - JetBrains Mono Nerd Font Regular fonts: - Inter — clean sans-serif UI font - Roboto / Roboto Mono / Roboto Serif — primary font family - Material Design Icons — icon font used by DMS and other widgets - Font Awesome — icon font used by various bars and prompts Enables fonts.fontconfig so the user-level fontconfig cache is managed by Home Manager.

---

## foxblatConfig

### `customHomeManagerModules.foxblatConfig.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable Foxblat presets for Moza Racing wheelbases. Foxblat is a fork of Boxflat — the Linux configuration tool for Moza Racing hardware (alternative to Pit House). This module places game-specific FFB presets into ~/.config/foxblat/presets/ tuned for the Moza R9 (9 Nm): - r9-acc.yml — Assetto Corsa Competizione (transparent FFB, 15% damper, 25% friction for anti-oscillation on direct-drive) - r9-ac.yml — Assetto Corsa 1 (25% damper, 25% friction) - r9-cyberpunk2077.yml — Cyberpunk 2077 with cp2077-wheel-mod-moza (720°, mod-generated FFB at 250 Hz; spring/damper pass-through at 100%) All presets include pedal sections with game-appropriate response curves. All values are stored in raw wire format (what is sent to the hardware), not UI percentages. Key conversions: - ffb-strength, damper, friction, inertia, speed: wire = UI% _ 10 - natural-inertia: 1:1 (factory default KS/GS = 1100) - set-_-gain: wire = UI% \* 2.55 - equalizers: 1:1, neutral = 100 Requires customNixOSModules.simracing.enable = true on the machine. Used on: anya.

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

### `customHomeManagerModules.kubeConfig.rpcu.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to deploy the RPCU (Zitadel OIDC) mgmt kubeconfig. Copies assets/kubeconfigs/oidc-mgmt-rpcu.kubeconfig to ~/.kube/configs/rpcu/oidc@mgmt.kubeconfig so kubeswitch can discover it automatically.

---

## kubeTools

### `customHomeManagerModules.kubeTools.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable the full Kubernetes toolchain. Installs a comprehensive set of Kubernetes CLI tools and utilities: Core: - kubectl — Kubernetes CLI - kubernetes-helm — Helm package manager - k9s — TUI cluster dashboard (config in k9sConfig.nix) - kubeswitch — multi-kubeconfig context switcher (kswitch alias) - kubelogin-oidc — OIDC authentication plugin for kubectl - kustomize — Kubernetes overlay management Inspection & debugging: - kubectl-neat — strip noisy fields from kubectl YAML output - kubectl-view-secret — base64-decode secrets in-place - kubectl-explore — interactive resource browser - skopeo — inspect/copy container images without pulling - dive — explore container image layers - netfetch — network debugging tool - kubevirt — virtctl for KubeVirt VMs (SSH, console) - fluxcd — Flux GitOps CLI (flux) Custom packages: - kl — opinionated multi-pod log viewer - songbird — custom cluster management utility - pvmigrate — Proxmox VM migration tool - crd-wizard — CRD visualisation dashboard (Shift-E in k9s) - kratix-cli — CLI to build Kratix Promises (kratix) - sofka — Kubernetes TUI reimagined in Rust (ki alias) - sou — container image analysis wrapper Others: - kubebuilder — Kubernetes controller scaffolding - kind — local Kubernetes clusters via Docker - paralus-cli — Paralus zero-trust access CLI Also sets: - k=kubectl shell alias - ki=sofka shell alias - pctl=cli shell alias - kubectl and songbird Zsh completions See also: kubeConfig.\* options for OIDC kubeconfig file deployment, and k9sConfig.nix for k9s settings and plugins.

---

## kubeswitchConfig

### `customHomeManagerModules.kubeswitchConfig.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable kubeswitch context-switcher configuration. kubeswitch (exposed as the `kswitch` command) is a terminal UI and CLI for switching between multiple kubeconfigs / contexts stored across many files. This replaces the traditional KUBECONFIG env-var juggling. Configuration: - commandName: kswitch (aliased as `ks` in the shell) - Zsh integration enabled (shell function injection) - Fish integration enabled when fishConfig is active - Store: filesystem, scanning ~/.kube/configs/\*_ for files matching *.* (picks up all kubeconfigs deployed by the kubeConfig._.enable options) - Kind: SwitchConfig v1alpha1 Requires kubeTools.enable = true to have the kubeswitch binary available. Used on: totoro, nishinoya.

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

### `customHomeManagerModules.opencodeConfig.ollama.baseUrl`

- **Type:** `string`
- **Default:** `"http://localhost:11434/v1"`

The base URL for the Ollama API endpoint.

### `customHomeManagerModules.opencodeConfig.ollama.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable the Ollama provider for OpenCode. When enabled, configures an OpenAI-compatible Ollama provider with models defined in nixosModules/ollamaModels.nix.

---

## oversteerConfig

### `customHomeManagerModules.oversteerConfig.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to deploy Oversteer wheel profiles for Fanatec hardware. Oversteer is the Linux steering-wheel manager (rotation range, overall FFB gain, autocenter, combine-pedals, spring/damper/friction levels) that talks to the kernel hid-fanatec / universal-pidff driver. This module ships a game profile into ~/.config/oversteer/profiles/ tuned for the Fanatec CSL DD / GT DD Pro: - acc.ini — Assetto Corsa Competizione (900° base range, autocenter off for direct drive, neutral mechanical effects) IMPORTANT: Oversteer (and Linux in general) cannot set the detailed Fanatec base tune — FFB strength, NDP/NFR/NIN/FEI, etc. Those live in the wheelbase firmware and must be set on the base/wheel OLED tuning menu. This is the key difference from Moza, where foxblat can push the full base tune declaratively. So there is no full ACC FFB preset here, only the oversteer-level settings. An XDG autostart entry applies the ACC profile on login. Profiles can also be applied manually at any time with: oversteer -p acc --apply Requires customNixOSModules.simracing.enable = true on the machine (which installs oversteer and the Fanatec udev rules). Used on: hanamichi. Reference: https://github.com/berarma/oversteer

---

## rbwConfig

### `customHomeManagerModules.rbwConfig.baseUrl`

- **Type:** `string`
- **Default:** `"https://pass.bealv.io"`

The base URL for the Bitwarden server.

### `customHomeManagerModules.rbwConfig.email`

- **Type:** `string`
- **Default:** `*none*`

The email address for the Bitwarden account.

### `customHomeManagerModules.rbwConfig.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable rbw (Bitwarden CLI) with a selfhosted base url.

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

Whether to enable SSH client configuration. Configures programs.ssh with sensible keep-alive defaults applied to all hosts (Match \*): - compression: false — disabled to reduce CPU overhead on fast links - serverAliveInterval: 10s — send a keep-alive every 10 seconds - serverAliveCountMax: 2 — disconnect after 2 missed keep-alives (20s) enableDefaultConfig = false so NixOS's generated defaults do not conflict with this configuration. YubiKey SSH authentication is supported via two methods: 1. GPG-based: GnuPG agent with enableSSHSupport (nixosModules/tools.nix) uses GPG authentication subkeys stored on the YubiKey smart card. 2. FIDO2-based: ed25519-sk / ecdsa-sk keys via libfido2 (nixosModules/tools.nix). Generate with: ssh-keygen -t ed25519-sk For resident keys stored on YubiKey: ssh-keygen -t ed25519-sk -O resident SSH keys are managed separately via agenix secrets.

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

## vscode

### `customHomeManagerModules.vscode.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable Visual Studio Code with a declarative extension set. Manages VSCode entirely through Home Manager (mutableExtensionsDir = false), ensuring the extension list is reproducible and version-pinned. Extensions (200+, defined in extensionsList.nix): Languages: Go, Rust, Python (Pylance + pylint + black), TypeScript, Nix, Ansible, Terraform/OpenTofu, YAML, TOML, Markdown, Docker, Kubernetes, Helm, SQL, Java, C/C++, HTML/CSS AI assistants: GitHub Copilot (inline + chat), Continue Git: GitLens, Git Graph, GitHub Pull Requests Formatting: Prettier, EditorConfig, run-on-save (golines for Go, nixfmt for Nix files) UI/UX: Material Theme, Material Icons, indent-rainbow, Error Lens, Project Manager, Todo Tree User settings (profiles.default.userSettings): - Go: golines formatter (max line length 140) on save - Nix: nixfmt on save via emeraldwalk.runonsave - Python: Pylance language server, pylint linter, black formatter - Ansible: full OIDC collection names, lint enabled - GitHub Copilot: inline suggestions (3), completions (10) - kitty integration: sets kitty as external terminal Extra packages installed alongside VSCode: - exercism — coding challenge CLI - golines — Go line-length formatter - nixfmt — Nix code formatter Used on: nishinoya.

---

## zenBrowserConfig

### `customHomeManagerModules.zenBrowserConfig.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable the Zen Browser, a privacy-focused Firefox fork. Configures Zen Browser (twilight) via its Home Manager module with sensible defaults: telemetry and studies disabled, tracking protection enabled, Pocket disabled, and smooth scrolling turned on. When enabled, sets Zen as the default browser for http/https/html MIME types.

### `customHomeManagerModules.zenBrowserConfig.offerToSaveLogins`

- **Type:** `boolean`
- **Default:** `false`

Whether to let Zen Browser offer to save passwords. When false (default), the OfferToSaveLogins policy and signon.rememberSignons setting are disabled so the browser never prompts to save logins. Set to true to enable the built-in password manager and the "ask to save passwords" prompt.

---

## zshConfig

### `customHomeManagerModules.zshConfig.enable`

- **Type:** `boolean`
- **Default:** `false`

Whether to enable Zsh with full shell integrations and common tooling. Enables programs.zsh with: - oh-my-zsh framework - zsh-syntax-highlighting plugin (v0.8.0) — real-time command colouring - zsh-bat plugin — replaces `cat` output with bat syntax highlighting - Autosuggestions (fish-style inline suggestions) - any-nix-shell integration: preserves the Zsh shell inside `nix shell` and `nix develop` environments instead of dropping to bash Shell integrations (from commonShellConfig): - atuin — shell history search/sync (up-arrow disabled, manual Ctrl-R) - yazi — terminal file manager (y alias) - zoxide — smarter `cd` replacement (cd aliased to `z`) - fzf — fuzzy finder with tmux integration - eza — modern `ls` replacement - direnv — per-directory environment loading (nix-direnv enabled) Common packages installed: ginx, trippy, any-nix-shell, duf, sd, viddy, witr, dgop, devenv (see commonShellConfig.nix for the full list). Common aliases: ks=kswitch, watch=viddy, y=yazi, top=dgop, df=duf, cd=z, neofetch=fastfetch, gfix/gfeat/gchore (goji shortcuts).
