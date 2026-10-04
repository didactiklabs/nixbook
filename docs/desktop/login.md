# Login (greetd)

`customNixOSModules.greetd` runs the [greetd](https://sr.ht/~kennylevinsen/greetd/) login manager with one of two greeters:

```nix
customNixOSModules.greetd = {
  enable = true;
  greeter = "nixbook-shell";  # or "tuigreet"
  themeUser = "alice";        # nixbook-shell greeter: whose look to follow
  cursorUser = "alice";       # nixbook-shell greeter: whose cursor to show
};
```

The default greeter is **nixbook-shell's** login screen when a user of the machine runs nixbook-shell, otherwise **tuigreet**. A compositor module (`niri` or `sway`) must be enabled: the session list is built from the enabled compositors.

## tuigreet

A text-mode greeter with a clock, the last user and session remembered, a masked password field and a user menu. Niri sessions are started through `niri-session`.

## nixbook-shell login screen

The shell's own Quickshell greeter, styled like the user's desktop: the theme and variant, palette, fonts, account picture, cursor and login wallpaper chosen in the shell's Settings. It runs in Niri (cage as fallback, and tuigreet if neither starts, so there is always a login prompt). See [Lock & login screens](/nixbook-shell/lock-and-login#login-screen).

## Authentication

Either way, greetd's PAM service supports **U2F security keys**, **fingerprints** and **GNOME Keyring** unlock, and both greeters display PAM's prompts ("Touch your security key", fingerprint).

## Auto-login

A profile can skip the greeter entirely, as anya does:

```nix
services.greetd.settings = rec {
  initial_session = {
    command = "${pkgs.swayfx}/bin/sway";
    user = "khoa";
  };
  default_session = initial_session;
};
```
