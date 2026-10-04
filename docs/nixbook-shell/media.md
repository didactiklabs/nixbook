# Media & phone

## Players

The shell follows every MPRIS player (Spotify, browsers, mpv, YouTube Music, phone players via KDE Connect) and lets you pick which one the controls drive:

- a **source selector** — _Auto_ plus one chip per player, with its icon and a playing pulse — at the top of the media popup and the sidebar player; **scroll** the bar's media widget or the dock card to switch;
- _Auto_ follows your preferred player, then the last one that started playing;
- **per-player volume**: the volume controls act on the player's own PipeWire stream (browsers and Electron players ignore MPRIS volume);
- transport controls: previous/next, ±10 s seek, shuffle, repeat;
- a **⋯ menu** with what the player supports: stop, fullscreen, the track link (copy, open, **send to your phone**), play a link from the clipboard, _Up next_, playlists, raise or quit the player.

## Equalizer

The equalizer panel drives **EasyEffects**: presets or a 10-band curve with preamp, or **Auto**, which picks a curve from the song's Last.fm genre tags. Its optional **agent mode** has a small Claude Code task (Haiku by default) tune the curve for each new song (`equalizer.agent`, `equalizer.agentModel`).

## Music recognition

The music-recognition toggle and widget listen to what is playing and identify it with **songrec** (Shazam), keeping a list of the songs found.

## Phone Connect

The **Phone Connect** bar widget brings KDE Connect into the bar:

- the device icon with its battery (red at 15 % or less unless charging);
- a panel with each device's battery and signal, and actions — **ring / find**, ping, **send the clipboard**, **share a file**, **browse** the phone's files, open SMS, take a photo — limited to what the device supports;
- pairing requests with the verification key (accept, reject, unpair).

Phone players appear in the media source selector, and notifications mirrored from the phone are [de-duplicated](./notifications#duplicates) against the desktop's.
