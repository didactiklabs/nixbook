# Theming & fonts

## Stylix

[Stylix](https://github.com/danth/stylix) (`customHomeManagerModules.stylixConfig`, on by default) applies one colour palette to every supported application — terminals, editors, GTK, bars:

- **dark** polarity, generated from the wallpaper `profileCustomization.mainWallpaper` (set per profile);
- every Stylix target enabled, except those that theme themselves: DankMaterialShell (matugen), k9s, and — with nixbook-shell — Qt and Zen Browser, which the shell colours like itself;
- the **phinger-cursors** cursor (24 px) and the Roboto fonts.

::: info Desktop shells pin a stable palette
With a Quickshell desktop shell (DankMaterialShell or nixbook-shell), Stylix uses the **tomorrow-night** base16 scheme instead of the wallpaper-derived one. For many wallpapers the derived palette collapses into near-identical shades (e.g. every colour a shade of purple), which makes terminals unreadable; the shells draw their own Material accent from the wallpaper anyway.
:::

Set the wallpapers per user:

```nix
profileCustomization = {
  mainWallpaper = ./wallpaper.png;
  lockWallpaper = ./lock.png;
};
```

## GTK

`customHomeManagerModules.gtkConfig` — a consistent dark GTK 2/3/4 look: Papirus-Dark icons, the Numix themes, dark preference everywhere, light hinting with RGB subpixel rendering, and the accessibility modules.

## Qt

Every user gets qt5ct/qt6ct with the Adwaita dark style (`mkUser`). With nixbook-shell, Qt and KDE apps follow the shell's palette live — see [App colours](/nixbook-shell/themes#app-colours).

## Fonts

`customHomeManagerModules.fontConfig`:

| Role       | Default font     |
| ---------- | ---------------- |
| Sans-serif | Roboto           |
| Serif      | Roboto Serif     |
| Monospace  | Roboto Mono      |
| Emoji      | Noto Color Emoji |

Plus FiraCode and JetBrains Mono **Nerd Fonts** (icons in the terminal), Inter, Material Design Icons and Font Awesome. nixbook-shell ships its own faces (Google Sans Flex, Space Grotesk, Readex Pro, and the theme fonts).

## Cursors

Stylix sets the shared cursor; a profile can override it — hanamichi uses the **Momonga** Xcursor theme stored in its profile assets.
