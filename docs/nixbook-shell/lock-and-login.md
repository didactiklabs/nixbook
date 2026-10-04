# Lock & login screens

## Login screen

On NixOS, the shell can be the **login screen** too: greetd runs `nixbook-shell greeter` with one user's look — theme and variant, palette, fonts, account picture and cursor — drawn in the theme's style (a frosted card for Material, a slanted frame with slash and halftone for Persona, the character peeking over a bubbly card for Chiikawa…) under the date and a large clock.

- Pick the account with the pictures under the card, or Up/Down.
- The password field (the eye shows it, Esc clears it) and PAM's cues: **security key**, **fingerprint**, further prompts such as a one-time code.
- The **session** pill (click or scroll to switch) — remembered with the last user.
- Suspend, reboot and power off in the corner.

In nixbook, enable greetd and it becomes the default greeter when a user runs nixbook-shell ([Login](/desktop/login)). Standalone, with the shell's NixOS module:

```nix
nixbook-shell.greeter = {
  enable = true;
  user = "alice";          # whose look it follows (null: the default look)
  cursorUser = "alice";    # whose cursor it shows (default: user)
  background = ./login.jpg; # optional default login wallpaper
};
```

The greeter can't read your home directory, so a small service exports what it needs (the look's settings, palette, account picture, wallpaper) to `/var/lib/nixbook-shell-greeter` whenever they change. It runs in Niri — which shows the theme's colour and wallpaper from its first frames and takes over Plymouth without a blank screen — with cage as fallback and tuigreet if neither starts, so there is always a login prompt.

## Loading screen

After login, the shell's **loading screen** covers the session from its first frame until the shell is fully drawn, then fades out: no black screen or half-drawn desktop in between (`programs.nixbook-shell.splash.enable`, on by default). It waits until rendering is smooth rather than a fixed delay, and desktop widgets fade in afterwards.

## Account picture

**Settings → Profile → Avatar** sets your picture through AccountsService (the one login screens use; `~/.face` as fallback): choose an image or pick one from your pictures folder. It appears in the sidebars, the user-card widget, the lock screen and the greeter.

## Lock screen

**Mod+L → Lock**, `nixbook-shell ipc call lock activate`, or after 1 minute idle ([hypridle](/desktop/#idle-and-locking-niri)) locks the session:

- the theme's lock screen over the lock wallpaper (or the desktop's), with the clock;
- **U2F security keys** — a pulsing _"Touch your security key"_ pill while PAM waits — and fingerprints;
- GNOME Keyring is re-unlocked with your password.

The lock is **crash-safe**: while locked, a marker file exists; if the shell ever crashes, systemd restarts it and it locks again at once, so the real lock screen comes back within seconds (Niri keeps the session locked meanwhile).

## Polkit prompts

The shell is the session's **polkit agent** (set `customNixOSModules.niri.polkitAgent = false` so polkit-gnome doesn't take the registration): privilege prompts are themed and take the keyboard immediately.
