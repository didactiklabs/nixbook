# macOS (talia)

nixbook also manages Macs, with [nix-darwin](https://github.com/nix-darwin/nix-darwin) and the same Home Manager modules as the NixOS machines. **talia** (khoa's Mac) is the first one.

| Machine | Hardware                 | User | Window manager                           |
| ------- | ------------------------ | ---- | ---------------------------------------- |
| talia   | Apple Silicon, macOS 26+ | khoa | [OmniWM](https://omniwm.app) (niri-like) |

## How it fits

colmena only deploys NixOS, so the Macs aren't in `hive.nix`: `darwin.nix`, next to it, lists them with the same pins (`npins/`) and the same nixpkgs instance (`lib/pkgs.nix`, with `system = "aarch64-darwin"`).

```
darwin.nix                    the macOS machines (talia; withUser: the same for another account)
├── darwinModules/            system modules (customDarwinModules.*)
│   ├── core.nix              Nix daemon (Lix, nixbook's cache, pinned nixpkgs), Touch ID sudo, zsh, GC
│   ├── defaults.nix          macOS preferences for a tiling window manager
│   ├── caCertificates.nix    the internal CAs in Nix's trust store
│   └── tools.nix             darwin-switch
├── lib/darwinUserConfig.nix  the Home Manager user (mkUser, home in /Users)
└── profiles/talia/           the machine and its user (khoa/)
```

Everything that isn't Linux-specific comes along: zsh, starship, atuin, git, ssh, nixvim, kitty, the CLI and dev tools, Kubernetes tools, k9s, kubeswitch, goji, rtk, opencode, fastfetch, fonts and the stylix colours (tomorrow-night). The Linux desktop doesn't: niri, Sway, nixbook-shell, DankMaterialShell, GTK, fcitx5, Dolphin, the desktop entries. Those modules are still imported, so their options exist, but none of them is on, and `tests/darwin.nix` fails if one is switched on or a Linux desktop package ends up in the system.

## Setting up a Mac

What it needs:

1. An Apple Silicon Mac on macOS 26 (Tahoe) or later (OmniWM's requirement).
2. An **admin** account whose short name is the profile's user (`khoa` on talia), made in Setup Assistant as usual: nix-darwin uses the account, it doesn't create it.
3. Nix, from the [Lix installer](https://lix.systems/install/) (or upstream Nix). Not Determinate Nix: it runs its own daemon, and nix-darwin manages it here.
4. This repository: `nix run nixpkgs#git -- clone git@github.com:didactiklabs/nixbook.git ~/Documents/perso/nixbook` (no Xcode command-line tools needed).

The first switch (`darwin-switch` doesn't exist yet):

```sh
cd ~/Documents/perso/nixbook
$(nix-build darwin.nix -A talia.system)/sw/bin/darwin-switch
```

nix-darwin refuses to replace the `/etc/nix/nix.conf`, `/etc/bashrc` and `/etc/zshrc` the installer wrote: rename them to `*.before-nix-darwin` when it says so.

Then, once:

- System Settings → Privacy & Security → **Accessibility** and **Input Monitoring**: allow OmniWM (it asks at its first start).
- Log out and back in: "Displays have separate Spaces" (`system.defaults.spaces.spans-displays`) applies after a new login.
- If macOS asks to let the terminal manage apps (App Management), allow it.

## Updating

```sh
darwin-switch            # build darwin.nix's talia from the checkout and activate it
darwin-switch --build    # build only
```

`darwin-switch` is `colmena apply-local switch` for the Macs: it builds as you, then activates as root through `sudo` (Touch ID), which is why the account must be an admin. It uses the checkout the system was built from (`NIXBOOK_REPO` or `--repo` for another one) and this machine's name (`--host`).

## Apps and the default browser

talia gets the apps of totoro that nixpkgs builds for macOS: Vesktop, Slack, Spotify, YouTube Music, Moonlight, Anki, LibreOffice, mpv, Zen (`zenBrowserConfig`) and rbw (Bitwarden, its password asked in macOS's own dialog). Home Manager copies them into `~/Applications/Home Manager Apps` (`targets.darwin.copyApps`), so Spotlight and Launchpad find them. Not on macOS: Nextcloud's client, KDE Connect, OBS, Actual Budget, Meru, Moonfin.

**Zen is the default browser.** macOS has no silent way to set it: each switch checks whether Zen is the default and, when it isn't, asks for it (`defaultbrowser`), and macOS shows a "change your default web browser?" dialog to confirm. So it's asked once, and again only if the default is changed back.

## OmniWM

[OmniWM](https://omniwm.app) is a tiling window manager with niri's scrolling columns. `customHomeManagerModules.omniwmConfig` installs it (nixpkgs' `omniwm`, Home Manager's `programs.omniwm`) and starts it at login (a launchd agent).

**Settings.** OmniWM 0.8 rejects a `settings.toml` missing any required key, so Nix can't write the file from the few keys it sets. The file stays OmniWM's own (written at its first start, editable in its Settings window); the keys and hotkeys set in `omniwmConfig.settings` and `omniwmConfig.hotkeys` are merged into it (`homeManagerModules/omniwm/apply-settings.py`) at each switch and whenever the file changes (a second launchd agent watches it). A key set in Nix is put back when changed in OmniWM's window; every other key is OmniWM's to keep. Before OmniWM has written its file there is nothing to merge into: the agent applies the keys as soon as the file appears. The first version of the file is kept as `settings.toml.before-nixbook`; the agent's messages go to `~/Library/Logs/omniwm-nix-settings.log`.

```nix
customHomeManagerModules.omniwmConfig = {
  enable = true;
  settings.gaps.size = 8.0;              # a float where OmniWM reads floats
  hotkeys."focus.left" = "Option+H";     # an action already on Option+H is unassigned
};
```

The defaults mirror niri's layout (gaps 10, column widths ⅓ ½ ⅔ ⅘, new columns ⅘, focus follows the mouse) and its keybindings with **Option** as niri's Mod key: see [Keybindings](/desktop/keybindings#omniwm-macos). OmniWM's own updater is off (the app comes with nixbook).

## Trying it on a Mac that isn't yours

`darwin-try` (devenv shell, `tests/darwin-try.sh`) puts a machine of `darwin.nix` on a Mac you can throw away, for its own account (`withUser HOST USER` builds any machine for any account): it installs Lix there, copies the checkout in (`~/nixbook`), builds the machine and switches the Mac to it. Run the same command again after a change.

```sh
darwin-try remote m1@51.159.x.x      # a Mac reached by ssh, e.g. a rented one (talia by default)
darwin-try vm up                     # on an Apple Silicon Mac: a tart VM in a window
darwin-try vm switch | ssh | stop | delete
```

**Without a Mac**, rent one for a day: Apple silicon Mac minis by the hour (for example Scaleway's, with macOS 26; Apple's licence sets a 24-hour minimum), reached by ssh, their desktop by VNC (Screen Sharing). That's the real thing (OmniWM, the keybindings, macOS itself) for a few euros. A Linux PC can't stand in: it only runs x86 macOS, against Apple's licence, and OmniWM needs Apple Silicon. The window management is niri's model, so the feel of the columns is the one niri gives on the Linux machines; what differs is macOS around it.

**On a Mac**, `darwin-try vm` runs [tart](https://tart.run) (Apple's Virtualization framework) with Cirrus Labs' macOS 26 base image (user `admin`, password `admin`; ~25 GB the first time), so the Mac itself isn't touched.

Either way, then: allow OmniWM under Accessibility and Input Monitoring, log out and back in, and try `Option+Return`, `Option+Left/Right`, `Option+Tab`.

## Tests

- `tests/run.sh darwin` (CI's `darwin` job, on Linux): each Mac evaluates without import from derivation, keeps its invariants (`tests/darwin.nix`: no Linux desktop module on, OmniWM set up, separate Spaces, darwin-switch installed), and has no Linux desktop package in its closure; the OmniWM settings merge (`tests/omniwm-settings.sh`).
- `build (talia)` in `build.yaml`: on a GitHub macOS runner (a VM), `tests/darwin-switch.sh` builds talia for the runner's user (`withUser`), switches the runner to it as `darwin-switch` does, and checks the result: the system, `/etc/nixos/version`, nixbook's `nix.conf`, Touch ID sudo, the OmniWM agents, the user's tools, zsh. OmniWM itself can't run there (it needs the Accessibility permission).
