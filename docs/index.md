---
layout: home

hero:
  name: Nixbook
  text: Your whole fleet, as code
  tagline: A reproducible NixOS configuration for Wayland laptops and desktops — bootloader to desktop shell, one repository, one command.
  image:
    src: /logo.svg
    alt: Nixbook
  actions:
    - theme: brand
      text: Get started
      link: /guide/introduction
    - theme: alt
      text: Install a machine
      link: /installation/
    - theme: alt
      text: View on GitHub
      link: https://github.com/didactiklabs/nixbook

features:
  - icon: ❄️
    title: Reproducible by design
    details: Every dependency is pinned with npins. The same commit builds the same system on any machine, and NixOS generations make every update atomic and reversible.
    link: /guide/architecture
  - icon: 🖥️
    title: One repo, many machines
    details: Per-hostname profiles pick their modules and users. Colmena deploys locally, and an installer ISO provisions a new machine from bare metal.
    link: /machines/
  - icon: 🧩
    title: Opt-in modules
    details: Around 20 NixOS modules and 35 Home Manager modules — gaming, sim racing, VPNs, printing, Secure Boot, Kubernetes tooling — each switched on per machine.
    link: /reference/options
  - icon: 🪟
    title: Modern Wayland desktop
    details: Niri (scrollable tiling) or SwayFX, with DankMaterialShell or nixbook's own Quickshell desktop shell, themed from the wallpaper.
    link: /desktop/
  - icon: ✨
    title: nixbook-shell
    details: A complete desktop shell — bar, dock, sidebars, launcher, notifications, lock and login screens, desktop widgets and five themes, configured from Nix or its own Settings window.
    link: /nixbook-shell/
  - icon: 🤖
    title: AI agents on the desktop
    details: A guarded MCP server lets Claude Code and other agents see and drive the desktop — or work on a sandboxed desktop of their own — with a pause button and an audit log.
    link: /nixbook-shell/desktop-agents
  - icon: 🔐
    title: Secure by default
    details: UEFI Secure Boot with automatic key enrolment, LUKS encryption, agenix secrets, U2F security keys, kernel hardening and an opt-in nftables firewall.
    link: /system/security
  - icon: 🛠️
    title: A full dev toolchain
    details: Zsh with modern CLI replacements, NixVim, VS Code, Kubernetes tools, AI commit messages, isolated AI coding workspaces and a reproducible devenv.
    link: /user/development
  - icon: ✅
    title: Tested on every push
    details: Cheap evaluation checks on GitHub runners, full builds of only the machines a change touches, and a signed binary cache pushed from main.
    link: /development/ci-cd
---
