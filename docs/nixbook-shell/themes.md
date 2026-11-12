# Themes & colours

## Choosing a theme

The theme is `appearance.theme`. Switch it from:

- **Settings → Themes**;
- the desktop's right-click menu → _Theme_;
- the **launcher's theme mode** — **Mod+X**, or type the `@` prefix: every theme and variant, type to filter, Enter applies;
- an AI agent (`set_theme`: "switch to Persona 3 Reload").

| Theme       | Variants                                                  | Look                                                                                                                                                                   |
| ----------- | --------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `material`  | —                                                         | The default: colours from the wallpaper, Material 3 tonal elevation (surfaces told apart by tone and a thin outline, no shadows)                                       |
| `persona`   | `p5` (Royal, default), `p3r` (3 Reload), `p4` (4 Revival) | Slanted black panels with bold outlines, hard unblurred offset shadows, accent slashes and halftone art; notifications as the in-game phone chat                       |
| `chiikawa`  | `chiikawa` (default), `usagi`, `momonga`                  | Pastel light palettes, bubbly corners, bouncy motion and an animated Momonga                                                                                           |
| `cyberpunk` | `yellow` (default), `red`, `cyan`                         | Cyberpunk 2077, after its UI art: hairline HUD frames with cut corners, notched edges, rulers and caps tags; in-world screen wallpapers, glitch effects, Rajdhani type |
| `ghibli`    | `totoro` (default), `spirited`, `mononoke`                | Studio Ghibli: painted wallpapers, the films' spirits in the corners, Zen Maru Gothic and Klee One type                                                                |

```nix
programs.nixbook-shell.settings.appearance = {
  theme = "chiikawa";          # an enum: a typo fails evaluation
  chiikawa.variant = "usagi";  # likewise for the variants
};
```

Each theme keeps its own variant (`appearance.<theme>.variant`), so switching away and back restores it. Themes with variants also have per-part switches — `palette`, `motion`, `shapes`, `fonts`, and theme extras such as Persona's `halftone`, Chiikawa's `mascot`, Cyberpunk's `glitch` and `frames` (the HUD frames behind the panels) or Ghibli's `spirits` — to take only part of a theme.

## Wallpapers per theme

With `appearance.wallpaperPerTheme` (on by default), each variant keeps its **own desktop, lock-screen and login-screen wallpapers**: switching variant puts back what it had (the first time, the bundled wallpaper for Chiikawa, Cyberpunk and Ghibli), and a wallpaper picked while in a variant becomes that variant's. Settings → Themes shows them all in one table.

## Sounds and cut-ins

Each theme has its own **notification chime** and **critical sound** — Persona 5's by default, the Velvet Room's chime and the Evoker in Persona 3 Reload, the Midnight Channel's TV in Persona 4, the characters' little voices in Chiikawa, a message ping and an alert in Cyberpunk, the films' sounds in Ghibli. Apart from Persona 5's and Cyberpunk's two, which are audio files, they are **synthesized from scratch** at build time (no sample or melody is taken from the originals); a sound file set in the settings wins.

Important notifications get the theme's **cut-in** — see [Notifications](./notifications#cut-ins).

## Window animations

Under Niri, window open/close animations follow the theme: the shell fills a Niri animation template with its palette's colours and Niri reloads it live (nixbook ships the template — a Persona slash — and the include).

## Fonts

Google Sans Flex (main text, titles, numbers), Space Grotesk (desktop clock) and Readex Pro (AI chat), plus each theme's faces, are shipped with the shell and on the login screen, so nothing falls back to the system font (`appearance.fonts`).

## App colours

Other apps can follow the palette the shell shows (the wallpaper's or the theme's), each switched on under **Settings → Appearance → Color generation → Apps**:

| App               | How it gets the new colours                                                                                                                 |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| Qt & KDE          | Live: `kdeglobals` and a palette-changed signal; Qt apps through qt6ct/qt5ct (`programs.nixbook-shell.appTheming.qt.enable`)                |
| Vesktop           | Live, through its themes folder                                                                                                             |
| YouTube Music     | Live, through its Electron bridge; always dark (the app has no light look), in the theme's colours: surfaces, text, menus, the progress bar |
| Gmail (Meru)      | Live, through Meru's Electron bridge, in every account's Gmail page; light or dark as the palette is                                        |
| YouTube (ZenPlay) | Live, through ZenPlay's Electron bridge: its window (toolbar, splash) and YouTube itself; light or dark as the palette is                   |
| Websites (Zen)    | Live: every web page in the palette's surface, text and accent (Dark Reader's engine in nixbook's Zen extension); off by default            |
| Zen Browser       | At startup (its `userChrome.css`); while Zen runs, a notification offers to restart it                                                      |

The palette is made **readable** first: text colours get at least 4.5:1 contrast against every surface (outlines 3:1), so a pastel accent that works as a fill never becomes unreadable link or tab text. While the Qt switch is on, colour schemes that a KDE app pinned for itself are removed so it follows the shell. Slack is deliberately not themed.

**Websites (Zen)** puts every page you open in Zen in the theme's colours: [Dark Reader](https://darkreader.org)'s library (MIT, pinned in `nixbook-shell/npins`) runs in nixbook's Zen extension (`zen/pages-theme.js`) on the palette's surface and text colours (a dark palette makes pages dark, a light one light), with links and focus rings in its accent. A new palette reaches open pages at once (sent through the extension's bridge); a Zen started later gets the last one from its bridge. It changes how every site looks, so it is off until you turn it on; private windows are left alone. Sites with their own dark mode may look different than with it.

**YouTube (ZenPlay)** colours [ZenPlay](/packages/#zenplay)'s own window and the YouTube page it shows. YouTube draws nearly everything with design tokens set on the page's root, most of them under hashed names (`--tffc2fd3a644f6275`) that no stylesheet can name ahead of time, so the bridge runs a small script in the page (`electron/youtube.style.js`) that reads them from YouTube's own stylesheets: a token is a variable YouTube gives one value in its light look and another in its dark one, and that pair says what it is for (a surface, a text colour, an outline, a wash, the blue of links and buttons). Each gets the palette's colour for that role; what has one value in both looks (what is drawn over a video, the brand's red) and the other hues (the reds and greens of states) are left alone. A renamed token is picked up by itself. YouTube's own **Appearance** setting is set to the palette's look (light or dark) as its menu would, so what its server draws for a look (the description's text, the search box) matches too; with the switch off it goes back to following the device. The video's progress bar is the accent.

Gmail's colours come from [Catppuccin's Gmail userstyle](https://github.com/catppuccin/userstyles/tree/main/styles/gmail) (MIT), which follows Gmail's pages as they change: `nixbook-shell/scripts/gmail-template.py` compiles it with each Catppuccin colour mapped to a palette role (base → surface, text → on_surface, the accent → primary…) into `app-templates/gmail.css`. Its icon filters become a grey at the text's lightness (`.gray` in the templates). When Gmail changes and their style follows, bump the script's `REV` and run it again.

## Adding a theme

Themes are declared once, in `src/modules/common/themes.json`, which the shell, the Nix options, the login screen and Niri's first frames all read:

1. Add an entry: `id`, `name`, `icon`, `description`, `variants` (each with an optional `palette`), optional `defaultVariant` and `style` — corner rounding, fonts and motion curves as data — plus optional `wallpaper` and `sounds`.
2. With variants, add its `appearance.<id>` block in `src/modules/common/Config.qml` and regenerate the defaults with `nixbook-shell config builtin > builtin-defaults.json`.
3. For anything data can't express, add a singleton gated on `Themes.is("<id>")` and an options section in the Appearance page. Theme lists, variant pickers and menus come from the registry automatically.
