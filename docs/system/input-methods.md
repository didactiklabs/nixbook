# Input methods

Nixbook uses [fcitx5](https://fcitx-im.org) to type in several languages, configured per user with `customHomeManagerModules.fcitx5Config`.

## fcitx5

```nix
customHomeManagerModules.fcitx5Config = {
  enable = true;
  addons = with pkgs; [ fcitx5-mozc-ut fcitx5-gtk ];
  inputMethods = [ "keyboard-fr" "lotus" "mozc" "schnelle-umlaute" ];
  defaultLayout = "fr";
  defaultIM = "keyboard-fr";
  lotus = true;
  schnelleUmlaute = true;
};
```

- The Wayland frontend, with `QT_IM_MODULE`, `XMODIFIERS` and `INPUT_METHOD` set for Qt and XWayland apps.
- `inputMethods` is the ordered group; the default is US + Japanese (Mozc).
- **Ctrl+Space** cycles forward through the input methods, **Ctrl+Shift+Space** backwards.
- The fcitx5 helper and configuration launchers are hidden from the app launcher.

Common engines: `keyboard-us`, `keyboard-fr`, `keyboard-de`, `mozc` (Japanese), `unikey` (Vietnamese Telex/VNI), `lotus` (Vietnamese), `schnelle-umlaute` (German).

## Vietnamese: Lotus

[Lotus](https://github.com/LotusInputMethod/fcitx5-lotus) is a Vietnamese input method that injects keys through a privileged uinput server, so it needs both a user and a system part:

```nix
# NixOS (profile)
customNixOSModules.fcitx5-lotus = {
  enable = true;
  users = [ "alice" ];   # one fcitx5-lotus-server@<user> service each
};

# Home Manager (user)
customHomeManagerModules.fcitx5Config = {
  lotus = true;
  inputMethods = [ "keyboard-us" "lotus" ];
};
```

The system module adds a `uinput_proxy` user, a udev rule for `/dev/uinput` and a server instance per listed user.

## German: Schnelle Umlaute

`schnelleUmlaute = true` adds an addon that types umlauts with a **hold-letter + Space** gesture, without a German layout:

| Gesture              | Result    |
| -------------------- | --------- |
| hold `a` + Space     | ä         |
| hold `o` + Space     | ö         |
| hold `u` + Space     | ü         |
| hold `s` + Space     | ß         |
| Shift+letter + Space | Ä / Ö / Ü |

Releasing the key without Space types the normal letter, so ordinary typing is unaffected. Mappings can be tweaked with `schnelle-umlaute-editor`.

## Keyboard layout

The system keyboard is **French AZERTY** (`core`); profiles change the fcitx5 default layout per user (hanamichi uses US QWERTY). nixbook-shell's _Keyboard Layout_ bar widget shows the active one.
