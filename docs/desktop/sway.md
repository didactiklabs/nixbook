# Sway (SwayFX)

[Sway](https://swaywm.org) is an i3-compatible tiling compositor. Nixbook uses the [SwayFX](https://github.com/WillPower3309/swayfx) fork, which adds blur, rounded corners and shadows while staying compatible with standard Sway configurations.

## Enable it

```nix
# NixOS (profile)
customNixOSModules.sway.enable = true;

# Home Manager (user)
customHomeManagerModules.swayConfig.enable = true;
```

## What you get

- **SwayFX** with the Secret portal → GNOME Keyring and swaylock keyring re-unlock;
- `homeManagerModules/sway/swayConfig.nix`: key bindings, workspaces, gaps, input and output settings, startup commands;
- windows at 80 % opacity with shadows, blur and 10 px corner radius;
- media keys that also work while locked (`--locked` bindings);
- **swayidle** for idle management (toggled with **Mod+I**);
- workspace keys bound to the **AZERTY** digit row.

See the [Sway keybindings](./keybindings#sway-swayfx-i3-like-compositor-anya).

## On anya

anya, the gaming and streaming desktop, runs SwayFX with **auto-login** (greetd starts Sway for the user directly), Steam Big Picture at startup and a **headless output** used by [Sunshine](/system/gaming-and-streaming#sunshine) for remote play.
