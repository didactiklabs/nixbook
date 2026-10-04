# Themes & colours

## Choosing a theme

The theme is `appearance.theme`. Switch it from:

- **Settings → Appearance → Theme**;
- the desktop's right-click menu → _Theme_;
- the **launcher's theme mode** — **Mod+X**, or type the `@` prefix: every theme and variant, type to filter, Enter applies;
- an AI agent (`set_theme`: "switch to Persona 3 Reload").

| Theme       | Variants                                                  | Look                                                                                                                                             |
| ----------- | --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `material`  | —                                                         | The default: colours from the wallpaper, Material 3 tonal elevation (surfaces told apart by tone and a thin outline, no shadows)                 |
| `persona`   | `p5` (Royal, default), `p3r` (3 Reload), `p4` (4 Revival) | Slanted black panels with bold outlines, hard unblurred offset shadows, accent slashes and halftone art; notifications as the in-game phone chat |
| `chiikawa`  | `chiikawa` (default), `usagi`, `momonga`                  | Pastel light palettes, bubbly corners, bouncy motion and an animated Momonga                                                                     |
| `cyberpunk` | `yellow` (default), `red`                                 | Cyberpunk 2077: chamfered HUD panels, glitch effects, Rajdhani type                                                                              |
| `ghibli`    | `totoro` (default), `spirited`, `mononoke`                | Studio Ghibli: painted wallpapers, the films' spirits in the corners, Zen Maru Gothic and Klee One type                                          |

```nix
programs.nixbook-shell.settings.appearance = {
  theme = "chiikawa";          # an enum: a typo fails evaluation
  chiikawa.variant = "usagi";  # likewise for the variants
};
```

Each theme keeps its own variant (`appearance.<theme>.variant`), so switching away and back restores it. Themes with variants also have per-part switches — `palette`, `motion`, `shapes`, `fonts`, and theme extras such as Persona's `halftone`, Chiikawa's `mascot`, Cyberpunk's `glitch` or Ghibli's `spirits` — to take only part of a theme.

## Wallpapers per theme

With `appearance.wallpaperPerTheme` (on by default), each variant keeps its **own desktop, lock-screen and login-screen wallpapers**: switching variant puts back what it had (the first time, the bundled wallpaper for Chiikawa, Cyberpunk and Ghibli), and a wallpaper picked while in a variant becomes that variant's. Settings → Appearance → Theme shows them all in one table.

## Sounds and cut-ins

Each theme has its own **notification chime** and **critical sound** — Persona 5's by default, the Velvet Room's chime and the Evoker in Persona 3 Reload, the Midnight Channel's TV in Persona 4, the characters' little voices in Chiikawa, a message ping and the Relic malfunctioning in Cyberpunk, the films' sounds in Ghibli. They are **synthesized from scratch** at build time (no sample or melody is taken from the originals); a sound file set in the settings wins.

Important notifications get the theme's **cut-in** — see [Notifications](./notifications#cut-ins).

## Window animations

Under Niri, window open/close animations follow the theme: the shell fills a Niri animation template with its palette's colours and Niri reloads it live (nixbook ships the template — a Persona slash — and the include).

## Fonts

Google Sans Flex (main text, titles, numbers), Space Grotesk (desktop clock) and Readex Pro (AI chat), plus each theme's faces, are shipped with the shell and on the login screen, so nothing falls back to the system font (`appearance.fonts`).

## App colours

Other apps can follow the palette the shell shows (the wallpaper's or the theme's), each switched on under **Settings → Appearance → Color generation → Apps**:

| App         | How it gets the new colours                                                                                                  |
| ----------- | ---------------------------------------------------------------------------------------------------------------------------- |
| Qt & KDE    | Live: `kdeglobals` and a palette-changed signal; Qt apps through qt6ct/qt5ct (`programs.nixbook-shell.appTheming.qt.enable`) |
| Vesktop     | Live, through its themes folder                                                                                              |
| Zen Browser | At startup (its `userChrome.css`); while Zen runs, a notification offers to restart it                                       |

The palette is made **readable** first: text colours get at least 4.5:1 contrast against every surface (outlines 3:1), so a pastel accent that works as a fill never becomes unreadable link or tab text. While the Qt switch is on, colour schemes that a KDE app pinned for itself are removed so it follows the shell. Slack and YouTube Music are deliberately not themed.

## Adding a theme

Themes are declared once, in `src/modules/common/themes.json`, which the shell, the Nix options, the login screen and Niri's first frames all read:

1. Add an entry: `id`, `name`, `icon`, `description`, `variants` (each with an optional `palette`), optional `defaultVariant` and `style` — corner rounding, fonts and motion curves as data — plus optional `wallpaper` and `sounds`.
2. With variants, add its `appearance.<id>` block in `src/modules/common/Config.qml` and regenerate the defaults with `nixbook-shell config builtin > builtin-defaults.json`.
3. For anything data can't express, add a singleton gated on `Themes.is("<id>")` and an options section in the Appearance page. Theme lists, variant pickers and menus come from the registry automatically.
