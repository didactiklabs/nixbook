# Desktop applications

## Curated apps

`customHomeManagerModules.desktopApps`:

| Category           | Apps                                                                                                                                           |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| Documents & images | **zathura** (PDF), **imv** (images, default viewer)                                                                                            |
| Office             | **LibreOffice** (Writer, Calc, Impress, Draw…)                                                                                                 |
| Communication      | **Vesktop** (Discord with Vencord)                                                                                                             |
| Music              | **Spotify**                                                                                                                                    |
| Creation           | **OBS Studio**, **Pinta**                                                                                                                      |
| Displays           | **wdisplays** (arrange monitors)                                                                                                               |
| Browser            | **Firefox** (default for web links unless Zen is enabled)                                                                                      |
| Files              | **Dolphin** with plugins, Ark, kio-admin, thumbnails, GParted (`dolphinConfig`)                                                                |
| Video              | **mpv** with thumbfast, MPRIS and modernx; yt-dlp, [ytui](/packages/#ytui) (YouTube) and [jtui](/packages/#jtui) (Jellyfin) TUIs (`mpvConfig`) |

**mpv** plays at its high-quality profile (sharper upscaling, debanding, chroma from luma for cleaner colour edges) with a deep network cache for direct play. modernx's control bar has menus: the **audio** and **subtitle** buttons list the tracks to pick from (right click: the next one), and the **HD** button opens the picture menu, everything off until asked:

- **Anime A, B, C** (Anime4K, drawn art): restore then upscale (blurry or compressed sources), a softer restore (sharp ones), or denoise and upscale (grainy ones).
- **Film** (FSRCNNX): a clean upscale for live action, without Anime4K's painted look.
- **Sharpen** (adaptive-sharpen): a bit of bite for soft sources.
- **Smooth motion**: frame interpolation, 24 fps without judder on a 60 Hz screen; with any of the above, at a GPU and battery cost.

The keys: **Ctrl+1…5** for the modes, **Ctrl+0** off, **Ctrl+M** smooth motion ([keybindings](/desktop/keybindings)). `desktopApps.mpvUpscaleQuality` picks the networks: `fast` (default, for integrated GPUs) or `hq` (for a dedicated GPU). The Jellyfin player uses the same mpv, controls and menus.

Default applications (MIME): PDF → zathura, images → imv, video → mpv, folders → Dolphin, text → VS Code when installed, else NixVim in kitty.

## Zen Browser

`customHomeManagerModules.zenBrowserConfig` installs [Zen](https://zen-browser.app) (twilight), a privacy-focused Firefox fork, as the **default browser**, with telemetry, studies and Pocket disabled, tracking protection on and smooth scrolling. It does not offer to save passwords unless `offerToSaveLogins = true`.

With nixbook-shell, Zen follows the shell's colours ([app colours](/nixbook-shell/themes#app-colours)).

### Links that open in an app

`zenBrowserConfig.openInApps` (host → the command opening such a link) sends the links of some sites to their desktop app instead of a tab. On totoro, **YouTube Music links** (`music.youtube.com`) play in the YouTube Music app:

```nix
customHomeManagerModules.zenBrowserConfig.openInApps = pear-desktop.nixbookOpenLinks or { };
```

(`pear-desktop` being the package from `nixbookShellConfig.electronA11y`, bridged where nixbook-shell runs.)

- **Clicked or typed in Zen**: a small force-installed extension stops the page load and hands the link to the app (through its native messaging host). The page you clicked from stays as it was; a tab opened just for the link (a link opening a new tab, a middle click) is closed. Private windows are left alone, and when the app can't be started the page loads in Zen as usual.
- **Opened by other apps** (a link in Discord, Slack, a notification, `xdg-open`, `$BROWSER`): `http`/`https` links go through `nixbook-open-url`, which sends the listed hosts to their app and everything else to Zen.

Most Electron apps, YouTube Music included, ignore a link on their command line: the app opens it through nixbook-shell's [bridge](/nixbook-shell/desktop-agents#apps-and-browser-through-the-page), which loads it in the app's page, whether the app was already running (its window comes to the front) or is starting. Without nixbook-shell the app is not bridged, so `nixbookOpenLinks` is empty and links stay in Zen.

## Thunderbird

`customHomeManagerModules.thunderbirdConfig` installs Thunderbird; accounts are configured in its UI, since mail credentials are sensitive.

## Clean app launcher

`customHomeManagerModules.desktopEntriesConfig` (on by default) hides launcher entries that are not real apps — daemons, helpers, settings tools and duplicates (fcitx5 helpers, KDE Connect daemon entries, pinentry, portals, geoclue demos, `nixos-manual`, qt5ct/qt6ct…) — so the launcher shows only what you actually open.

## Per-profile apps

Profiles add their own packages with `home.packages`, for example Slack, Moonlight, Anki, and nixbook's [Actual Budget](/packages/#actual-budget) (AppImage) and [Pear Desktop](/packages/#pear-desktop) (YouTube Music) on totoro, and [Moonfin](/packages/#moonfin) (Jellyfin) on every profile.

## KDE Connect

KDE Connect runs for every user: phone notifications, clipboard sync, file sharing, remote input and media control. nixbook-shell adds a [Phone Connect bar widget](/nixbook-shell/media#phone-connect).
