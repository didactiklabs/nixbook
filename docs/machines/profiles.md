# Machine profiles

Each machine lives in `profiles/<hostname>/`:

```
profiles/totoro/
├── configuration.nix    imports base.nix with the hostname (identical in every profile)
├── default.nix          hardware, NixOS modules, users (mkUser)
├── fastfetchConfig.nix  machine-specific extras…
└── khoa/                the user's Home Manager configuration
    ├── default.nix      customHomeManagerModules.*, packages
    ├── niriConfig.nix   per-user compositor overrides (monitors…)
    └── …
```

## totoro

**Main development laptop** — ASUS Zenbook (AMD, `nixos-hardware` `asus/zenbook/um6702`, the NVIDIA GPU disabled, modesetting only).

- **System:** laptop power profile, greetd with nixbook-shell's login screen, Niri (its polkit agent off: the shell has its own), Secure Boot, CA certificates (RPCU, Bealv, DidactikLabs), Lotus Vietnamese input. AMD Panel Self Refresh on without Selective Update (`core.amdgpuPsr = "no-su"`).
- **Desktop:** Niri + [nixbook-shell](/nixbook-shell/), multi-monitor Niri configuration.
- **User (khoa):** CLI and dev tools, AI workspaces (ocm), Kubernetes tools with DidactikLabs/Bealv/RPCU kubeconfigs, NixVim, Goji, Atuin sync, Kitty, Zsh, Starship, kubeswitch, OpenCode, RTK, Zen Browser, rbw (Bitwarden), Slack, Moonlight, Anki, Actual Budget, YouTube Music (Pear Desktop).
- **Input methods** (Ctrl+Space): French AZERTY → Vietnamese (Lotus) → Japanese (Mozc) → German umlauts (Schnelle Umlaute).

## tanjiro

**Development laptop** — Framework 13-inch AMD AI 300 series (`nixos-hardware`).

- **System:** laptop power profile, greetd, Niri, Secure Boot, the [firewall](/system/security#firewall), Tailscale and NetBird, CA certificates, Lotus input, ClamAV (daemon + updater), OpenVPN 3 client, GlobalProtect VPN client.
- **Desktop:** Niri + nixbook-shell.
- **User (khoa):** the same development environment as totoro (RPCU kubeconfig), OpenCode, RTK, Zen Browser, rbw.
- **Input methods:** French AZERTY → Vietnamese (Lotus) → Japanese (Mozc).

## nishinoya

**Secondary development laptop.**

- **System:** laptop power profile, greetd, Niri, CA certificates (DidactikLabs, LogicMG), unprivileged ports from 80 (`net.ipv4.ip_unprivileged_port_start = 80`).
- **Desktop:** Niri + [DankMaterialShell](/desktop/dms) (no dock).
- **User (aamoyel):** CLI and dev tools, AI workspaces, VS Code, Kubernetes tools with DidactikLabs/LogicMG/RPCU kubeconfigs, NixVim, Goji, Atuin, kubeswitch, fcitx5.

## hanamichi

**Everyday and gaming desktop** — NVIDIA RTX 3080 (proprietary driver, open kernel modules, modesetting).

- **System:** greetd with nixbook-shell's login screen, Niri, [gaming](/system/gaming-and-streaming#gaming) (`gpu = "nvidia"`: no Steam auto-launch), [sim racing](/system/gaming-and-streaming#sim-racing) (Fanatec), [printing and scanning](/system/hardware#printing-and-scanning), Lotus input. No work certificates or kubeconfigs.
- **Desktop:** Niri + nixbook-shell, the Momonga cursor theme (a profile asset).
- **User (chocomooncake):** VS Code, NixVim, Zen Browser (offers to save logins), desktop apps, Oversteer wheel profile.
- **Input methods:** US QWERTY → Vietnamese (Lotus) → Japanese (Mozc) → German umlauts (Schnelle Umlaute).

## anya

**Gaming and streaming desktop** — AMD GPU.

- **System:** [gaming](/system/gaming-and-streaming#gaming) with AMD tuning, [sim racing](/system/gaming-and-streaming#sim-racing) (Moza), [Sunshine](/system/gaming-and-streaming#sunshine) streaming with a headless virtual display, SwayFX, OpenSSH, Wake-on-LAN, CA certificates. Tailscale and NetBird off. Sleep, suspend and hibernation are disabled.
- **Session:** greetd logs `khoa` straight into SwayFX (no greeter), and Steam Big Picture starts with the session and restarts if closed.
- **Extras:** Immich timers upload game screenshots (Cyberpunk 2077, The Witcher 3) to the photo server.
- **User (khoa):** Foxblat presets for the Moza wheelbase, Kitty, Zsh, NixVim, Zen Browser, OpenCode.
