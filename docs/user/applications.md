# Desktop applications

## Curated apps

`customHomeManagerModules.desktopApps`:

| Category           | Apps                                                                                                                                           |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| Documents & images | **zathura** (PDF), **imv** (images, default viewer)                                                                                            |
| Communication      | **Vesktop** (Discord with Vencord)                                                                                                             |
| Music              | **Spotify**                                                                                                                                    |
| Creation           | **OBS Studio**, **Pinta**                                                                                                                      |
| Displays           | **wdisplays** (arrange monitors)                                                                                                               |
| Browser            | **Firefox** (default for web links unless Zen is enabled)                                                                                      |
| Files              | **Dolphin** with plugins, Ark, kio-admin, thumbnails, GParted (`dolphinConfig`)                                                                |
| Video              | **mpv** with thumbfast, MPRIS and modernx; yt-dlp, [ytui](/packages/#ytui) (YouTube) and [jtui](/packages/#jtui) (Jellyfin) TUIs (`mpvConfig`) |

Default applications (MIME): PDF → zathura, images → imv, video → mpv, folders → Dolphin, text → VS Code when installed, else NixVim in kitty.

## Zen Browser

`customHomeManagerModules.zenBrowserConfig` installs [Zen](https://zen-browser.app) (twilight), a privacy-focused Firefox fork, as the **default browser**, with telemetry, studies and Pocket disabled, tracking protection on and smooth scrolling. It does not offer to save passwords unless `offerToSaveLogins = true`.

With nixbook-shell, Zen follows the shell's colours ([app colours](/nixbook-shell/themes#app-colours)).

## Thunderbird

`customHomeManagerModules.thunderbirdConfig` installs Thunderbird; accounts are configured in its UI, since mail credentials are sensitive.

## Clean app launcher

`customHomeManagerModules.desktopEntriesConfig` (on by default) hides launcher entries that are not real apps — daemons, helpers, settings tools and duplicates (fcitx5 helpers, KDE Connect daemon entries, pinentry, portals, geoclue demos, `nixos-manual`, qt5ct/qt6ct…) — so the launcher shows only what you actually open.

## Per-profile apps

Profiles add their own packages with `home.packages`, for example Slack, Moonlight, Anki, and nixbook's AppImage packages [Actual Budget](/packages/#actual-budget) and [Pear Desktop](/packages/#pear-desktop) (YouTube Music) on totoro, and [Moonfin](/packages/#moonfin) (Jellyfin) on every profile.

## KDE Connect

KDE Connect runs for every user: phone notifications, clipboard sync, file sharing, remote input and media control. nixbook-shell adds a [Phone Connect bar widget](/nixbook-shell/media#phone-connect).
