# Media & phone

## Players

The shell follows every MPRIS player (Spotify, browsers, mpv, YouTube Music, phone players via KDE Connect) and lets you pick which one the controls drive:

- a **source selector** — _Auto_ plus one chip per player, with its icon and a playing pulse — at the top of the media popup and the sidebar player; **scroll** the bar's media widget or the dock card to switch;
- _Auto_ follows your preferred player, then the last one that started playing; a source you picked hands back to _Auto_ while it is closed or has nothing loaded (an idle Jellyfin player) and another player has a track, and scrolling skips players with nothing loaded;
- **per-player volume**: the volume controls act on the player's own PipeWire stream (browsers and Electron players ignore MPRIS volume);
- transport controls: previous/next, ±10 s seek, shuffle, repeat;
- a **⋯ menu** with what the player supports: stop, fullscreen, the track link (copy, open, **send to your phone**), play a link from the clipboard, _Up next_, playlists, raise or quit the player.

## YouTube Music in the background

Your YouTube Music playlists, played without a window: the right sidebar's **YouTube Music** tab (Mod+N; Settings > Panels turns the tab off) lists them, Liked Music first. Click one for its songs, then **Play**, **Shuffle**, or a song to start from. In one of your own playlists, hover a song for its **remove** button: a first click asks, a second within 3 seconds takes the song out (in Liked Music, the like is taken back). Playlists made by others have no such button. The **Search YouTube Music** field above them searches the whole catalogue, songs first and then videos (covers, live versions, what isn't released as a song), once you stop typing or on Enter. Click a result to play it, with the rest of that list after it. Escape or the cross clears the search. It plays in mpv, audio only, and shows like any player: the bar, the media controls, the media keys and the synced lyrics. The tab has shuffle, previous, play/pause, next, repeat (off, the playlist, one song), the lyrics of the song it plays (whatever other player is open), a **playlist** button that adds the song playing to one of your playlists (Liked Music likes it, **New playlist** makes a private one), and the player's own volume: a slider and a mute button under the controls, which set this player's volume only, not the system's, and are kept for the next time.

### Offline listening

Songs can play without network:

- **Songs you listen to:** a song heard for 30 seconds is downloaded to this computer (turn it off with **Keep the songs I listen to**).
- **Whole playlists:** open a playlist and click its download button to keep all of it; new songs added to it come down too (it is looked at again every 3 hours).
- **On this computer** (after Liked Music) lists every downloaded song, the last played first.
- **Without network**, the tab says **Offline**: your playlists show as they were the last time, and only the downloaded songs play (the others are dimmed).

The download button next to Refresh opens **Offline listening**: the space used, how much it may use (1 to 32 GB, 4 GB by default), what is downloading, the kept playlists, **Free space** (the songs no kept playlist has) and **Remove everything**. When the space is full, the songs played longest ago make room; a kept playlist's songs never do (if the kept playlists alone fill it, the rest of them waits, and the page says so). The songs are yt-dlp's best audio as it comes (Opus or AAC, about 3–5 MB each), in `~/.cache/nixbook-ytmusic/offline`, downloaded one at a time at low priority by the player's service. From the command line: `nixbook-ytmusic offline status|keep ID|unkeep ID|set limit MB|set auto on|off|clear [--all]`.

The song playing has a seek bar with its time in the tab, and the dock's media card a thin progress line along its bottom edge: click or drag it to seek, hover it for the time.

**Signing in** (the tab, or Settings > Apps & accounts > YouTube Music):

1. Sign in to YouTube Music in your browser (Zen, Firefox, LibreWolf, Floorp, Waterfox, Mullvad Browser, Chrome, Chromium, Brave, Vivaldi, Edge, Opera, Thorium; Flatpak and Snap ones too) or in the YouTube Music app.
2. Click **Use my browser's session**. When several have a login, pick one (the most recent is the default).

The session (that login's YouTube cookies) is kept in your keyring, never in a file; **Sign out** takes it out (your browser stays signed in). Your browser renews those cookies as you use it, and YouTube Music then refuses the copy kept here (edits answered "401 not authorized", an empty library): the player copies the session again from the same browser, the same account only, and tries once more, so you only sign in again when that browser has signed out. The songs play without it; it's only tried for a song that won't play otherwise (age-restricted…).

**Last.fm**: **Sign in to Last.fm** opens Last.fm's page where you allow nixbook, then click **I've allowed it**. Last.fm asks for an API key: the YouTube Music app's is used when it is installed; on another computer, **Create an API key** (free, at once) and paste the key and the secret. **Use the YouTube Music app's sign-in** takes its Last.fm sign-in as it is. A song is scrobbled once it has played half its length or 4 minutes (songs over 30 seconds), and shown as now playing when it starts.

**Listening together** in the [Mesh](./mesh.md#listening-together) plays the friend's song in this background player once you are signed in, instead of opening the YouTube Music app.

Under the hood: `nixbook-ytmusic` (`programs.nixbook-shell.ytmusic.enable`, on by default) reads the library with [ytmusicapi](https://github.com/sigma67/ytmusicapi) and plays through mpv and yt-dlp, the next song's stream resolved while the current one plays (no pause between songs); its player (the `nixbook-ytmusic` user unit) starts when something plays and is the MPRIS player "YouTube Music (background)" only while a song is loaded. `nixbook-ytmusic control next|toggle|shuffle|repeat…` drives it from a terminal or a shortcut.

## YouTube videos

The right sidebar's **YouTube** tab (Mod+N; Settings > Panels turns the tab off) is YouTube without a browser:

- **Home**: the videos of your YouTube home page, as YouTube picks them for you.
- **Subscriptions**: the channels you're subscribed to (picture, name, subscribers); click one for its latest videos.
- **Search YouTube**: any video; the results come once you stop typing. **Paste a YouTube link** there instead (`watch?v=`, `youtu.be/`, Shorts, live, music.youtube.com) and that video shows at once: Enter (or a click) plays it, from the time in the link (`t=90`, `t=1m30s`) when it has one.

Click a video to play it in **mpv**, your mpv with its settings (controls, upscaling…); the music playing [in the background](#youtube-music-in-the-background) pauses. While it plays, a card at the top of the tab shows it with **play/pause** and **its own volume** (mpv's, not the system's); the next video starts at the volume you left there.

Click a video's **channel name** to see that channel's latest videos, newest first, with **More videos** to go further back; the arrow (or Escape) goes back. A channel's page has **Subscribe** (or **Subscribed**: click it, then **Unsubscribe?** to confirm), your YouTube subscriptions themselves.

**Copying links**: hover a video or a channel and click its link button; the playing video's card copies its link at the current moment (`&t=`), so whoever opens it lands where you are. **More videos** at the end of a list loads 30 more (150 at most), and the refresh button asks YouTube again; each page otherwise shows its last copy at once and is asked again when it's more than 10 minutes old. Live streams are marked **LIVE**.

DAI can do all of this for you too (its `youtube_videos` tool): find or play a video, list a channel's latest, pause, seek or change the video's volume, subscribe to a channel or no longer.

Home and Subscriptions need your YouTube session: the one [YouTube Music in the background](#youtube-music-in-the-background) signs in with (the same Google login), so there is nothing more to sign in to. Searching works without it.

Under the hood: `nixbook-ytmusic videos home|subscriptions|search` lists them through [yt-dlp](https://github.com/yt-dlp/yt-dlp) (its `:ytrec`, `:ytsubs` and `ytsearch` lists), which follows YouTube's pages as they change; the session is given to it as a cookie file only while it runs. `nixbook-ytmusic videos channels` lists your subscriptions (YouTube's channels page), `videos channel URL|VIDEO` a channel's Videos tab (a video's channel is found through YouTube's oEmbed when the list didn't give it). `nixbook-ytmusic watch ID --volume N` starts mpv, through niri, so it keeps playing when the shell restarts; the card finds it by the YouTube link mpv publishes over MPRIS and sets mpv's own MPRIS volume (`MprisController` never takes an mpv's PipeWire stream: every mpv shares the binary).

## Equalizer

The equalizer panel drives **EasyEffects**: presets or a 10-band curve with preamp, or **Auto**, which picks a curve from the song's Last.fm genre tags. Its optional **agent mode** has a small Claude Code task (Haiku by default) tune the curve for each new song (`equalizer.agent`, `equalizer.agentModel`). The curve it makes for a song is remembered (the last 500 songs, in `~/.local/state/quickshell/user/eq/agent-curves.json`): when that song plays again, the same curve comes back at once, with no new agent run.

## EasyEffects and the volume

With EasyEffects running, every app plays into its sink and EasyEffects plays the result on the default output, which is always a real device: the one you pick in the output list (right click the sound quick toggle), or the one WirePlumber picks when a device comes or goes. The volume slider, the volume keys and the mute are that device's, and EasyEffects' sink stays at 100 % underneath, so there is one volume.

EasyEffects' sink itself is not in the output list, and it is never left as the default output. If it becomes the default (picked in another mixer such as pavucontrol; WirePlumber then also came back to it each time the chosen device went away), the shell clears WirePlumber's stored output choices a second later and a real device takes over. With the sink as the default, EasyEffects chose the device by priority alone (speakers picked, earphones plugged in: the sound went to the earphones), and the device's own volume and mute stayed hidden under the sink's.

An app whose sound gets connected to nothing (it can happen when EasyEffects restarts) is connected back to the default output after 5 seconds, without switching the output by hand.

## Echo cancellation

For calls: what plays on the computer (music, a film, the other side of the call) stays out of your microphone, and background noise is reduced. It is a setting for the whole computer, every app: **Settings → Sound → Echo cancellation**, or the **Echo cancellation** quick toggle (add it from the quick toggles' edit mode), the switch in the audio input dialog (right click the microphone toggle), or the Mesh's listening-together bar. While it is on, an **Echo-cancelled microphone** is your default input, and calls using the default input move to it; turning it off brings your microphone back. It stays on across logins until you turn it off. To change which microphone it cleans while it is on, pick it in the audio input dialog: the canceller moves onto it (a second's gap) and stays your default input; the list then shows only real microphones. It stays on that microphone: when it disappears for a while (a suspend, unplugged) and comes back, the canceller goes back to it, and EasyEffects' input processing can't pull it away (that used to make a loop with no microphone in it, so apps recorded silence).

It is PipeWire's own WebRTC echo canceller (`module-echo-cancel`, with noise suppression), in the `nixbook-echo-cancel` user service: what the default output plays is the reference it removes, so nothing is rerouted, and switching to headphones keeps working. It works with EasyEffects (your microphone's effects come first). No AI. `programs.nixbook-shell.echoCancel.enable` (on by default) installs it; `nixbook-shell ipc call echoCancel on|off|toggle|status`.

It **rests while nothing records the microphone**: the canceller, its voice stage and the microphone itself only run while an app (a call, a recorder, a level meter) takes sound from the Echo-cancelled microphone, and stop a few seconds after the last one left. Leaving it on costs nothing while you only listen to music (it used to run whenever any sound played: 18 % of a processor core on totoro, with the microphone powered). Nothing to set; `status` says `recorded` and `resting`.

## Clearer voices in calls

While echo cancellation is on, voices in calls are made clearer in both directions, without AI: an equalizer, a compressor and a limiter. Two switches under **Settings → Sound → Echo cancellation**, both on by default; changing one restarts echo cancellation (about a second without microphone).

- **Mine, for the others** — before call apps record you, your voice is equalized for speech (nothing under 100 Hz, less of the boxy 300 Hz, more presence around 3 kHz and air above 8 kHz), then evened out: a quiet voice comes up about 13 dB, a loud one about 8, and nothing goes over −2 dB. Apps still record the **Echo-cancelled microphone**.
- **The others', for me** — call apps play through a **Call voices** output with the same treatment tuned for listening: a quiet speaker comes up about 19 dB and a loud one about 11 (two speakers 21 dB apart end up 13 dB apart). It then plays on your output device, and has its own line in the volume mixer.

Call apps are the ones whose name contains a word of `programs.nixbook-shell.echoCancel.callApps` (Vesktop, Discord, Slack, Zoom, Teams, Element, Signal, Telegram… by default). They never go through EasyEffects: its equalizer is tuned for the music playing (a different curve per song in Auto mode, with a negative preamp), not for voices. Without **Call voices** (echo cancellation or the switch off) they play straight on your output device. A change of the list applies from the next login (the rule is read when the sound server and each app start).

Calls in the web browser count too, in Zen and the other Firefox-based browsers: a tab whose title is one of `programs.nixbook-shell.echoCancel.callSites` (Google Meet, Jitsi Meet and Microsoft Teams by default) plays on **Call voices** like a call app. These browsers name each tab's sound after the tab's title, which is how a call tab is told from the others, when its sound starts: a YouTube or music tab isn't touched and keeps playing through EasyEffects as before. Chromium browsers give every tab's sound the same name, so their calls can't be told apart and are left as they are.

If the others find your voice too processed, turn the first switch off, or turn off the call app's own noise suppression and automatic gain: two of each in a row is often what sounds worse.

## Phone Connect

The **Phone Connect** bar widget brings KDE Connect into the bar:

- the device icon with its battery (red at 15 % or less unless charging);
- a panel with each device's battery and signal, and actions — **ring / find**, ping, **send the clipboard**, **share a file**, **browse** the phone's files, open SMS, take a photo — limited to what the device supports;
- pairing requests with the verification key (accept, reject, unpair).

Phone players appear in the media source selector, and notifications mirrored from the phone are [de-duplicated](./notifications#duplicates) against the desktop's.
