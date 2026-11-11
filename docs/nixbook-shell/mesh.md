# Mesh

The mesh lets a few people talk desktop to desktop over the internet: messages to everyone or to one person, and everyone's status. No desktop connects to another directly: they all go through an [ntfy](https://ntfy.sh) server, and nothing they send can be read there.

## What it does

- **Messages** to everyone, or to one person, with files. They are written in the right sidebar's **Mesh** tab (Mod+N), which lists the conversations (Everyone, then each person).
- **Nudges**: the **✨** button beside the field opens a picker of nudges (❤️ Love you, 💭 Thinking of you, 🤗 Sending you a hug, 🫳 Head pats — a hand patting the receiver's own picture, squashing it like the petpet meme, or a face in Everyone's conversation —, 👋 Hey!, ☀️ Good morning, 🌙 Good night, 🏃 On my way, 📞 Call me when you can?, ☕ Coffee break?, 🎮 Up for a game?…) and your own quick messages (`mesh.quickMessages`). The other person gets a nudge as its own cut-in: your picture and the emoji drop in under their bar with the words, for a few seconds; a click opens the conversation, right click sends it away, it never takes their keyboard. It shows even when they have the Mesh tab (or your conversation) open; it comes as a normal notification instead while they are locked or on Do Not Disturb (a fullscreen film or game still gets it), and when they turned **Show the nudges I receive as a cut-in** off (`mesh.nudgeCutIn`). An older desktop shows a nudge as its text.
- **Status**: free, in a meeting, gaming, busy (a fullscreen window), do not disturb, away (locked, screens off). It never says which app or window. It is sent when it changes, and again every 10 minutes; someone not heard from for 25 minutes shows as offline. How the others see you shows at the top of the Mesh tab ("You (Khoa): Free") and first in the bar widget's hover list. In order: not shared (the switch is off), away, do not disturb, in a meeting (a timed calendar event now), gaming (a Steam game or gamescope focused), busy (a fullscreen window), free.
- **Listening together**: share what your YouTube Music, Spotify or Jellyfin plays; the others listen (or watch) along, in sync. See [Listening together](#listening-together).
- **Files**: images and GIFs, shown in the conversation, and any other file (a PDF, an archive…), shown as a card. See [Files](#files).
- **Read receipts**: "seen" under your messages in a conversation with one person, and "seen by …" (a name, or how many) under your last message in Everyone's.
- **Deleting**: hover a message and click the bin, then again to confirm. See [Deleting a message](#deleting-a-message).
- **Links and copying**: links in messages open with a click (YouTube Music links straight in the YouTube Music app, open.spotify.com links in Spotify: never through the browser); drag over a message to select it (Ctrl+C copies, typing goes back to the field), or hover it and click the copy button for its whole text.
- **Replies**: hover a message and click the reply arrow (in its toolbar, with react, copy and delete): "Replying to …" shows above the field (✕ or Escape to cancel). The answer shows the message it answers quoted on top (its sender and a line or two of it); a click on the quote scrolls to that message and flashes it. The quote travels with the answer, so it shows even where the original isn't kept; a deleted original shows as such.
- **Reactions**: hover a message and click the smiley, then an emoji (`mesh.reactions`: 👍 ❤️ 😂 😮 😢 🙏). They show under the message with how many; yours are highlighted, and clicking one takes yours back or adds it; hover one to see who. A reaction to your own message gets a quiet notification (not while the Mesh tab is on screen). In a private conversation they are sealed like the messages.
- **Profile pictures**: your account picture (the one the login screen shows, Settings > Profile) goes to the others, as a 256 px square, encrypted like a file; it shows beside your messages in the Everyone conversation, on your conversation chip, at the top of your private conversation and on your notifications. It is sent again when it changes, and once a month (the server deletes files after a while). Turn it off with **Show my account picture to the others** (`mesh.shareAvatar`): the others then see your initial.
- **Notifications**: each message arrives as a notification named after its sender, with **Reply**, which opens the conversation. While the **Mesh** tab is on screen, they come without a cut-in, and the conversation open there gets none (it is marked read). On nixbook, a message to you alone gets the Persona cut-in, and every mesh message stays on screen like other chats (`hint:"nixbook-mesh-direct"`, `nixbook-mesh` in the notification rules).
- **The bar's mesh widget**: how many people are around, and unread messages. Hovering it lists everyone's status; a click opens the conversation that has something new.

**History**: each desktop keeps its last 500 messages (`~/.local/state/quickshell/user/mesh-conversation.json`): scroll up in a conversation (it shows the latest 60 and loads older ones as you scroll up; switching back to a conversation is instant, where you left it). The server keeps messages a year, so a desktop that was off catches up, and one that joins (or is reinstalled) gets the conversation so far, without others' private messages. Status updates older than 30 minutes are skipped when catching up. Two computers of the same person don't share their history.

Messages written while the computer was off arrive when it comes back (the server keeps them a year: `cache-duration` in `../atlas`). Messages older than two hours then count as unread, without a notification each.

## Files

Send files with the **clip button** beside the field (several at once), by **dropping** them on the Mesh tab, or by pasting a copied image or file (**Ctrl+V**; text still pastes as text). They wait above the field (✕ or Esc takes them back) and leave with the next message, the text with the first one.

- **Images and GIFs** (PNG, JPEG, GIF, WebP) show in the conversation, GIFs animated while the tab is in view. Click one to open it in your image viewer; right click, or the button in its corner, saves a copy in Downloads.
- **Other files** show as a card with their name and size, **Open** (with their app; a file that could run something, a script or a program, opens its folder instead) and **Save** (a copy in Downloads).
- While a file moves, its card shows how far it is. A failed send says why (click the message to try again); a failed download says why (click to retry).
- **Size**: the server decides. Hover the clip button to see its limit (on nixbook: `attachment-file-size-limit` in `../atlas`, `clusters/production/ntfy/cm.yaml`).
- **How long**: the server keeps files a year on nixbook's (`attachment-expiry-duration`; messages too, `cache-duration`), up to 10 GB each and 50 GB in all, then deletes them. Each desktop downloads a file up to 250 MB as soon as its message arrives and keeps it with the conversation (`~/.local/share/nixbook-shell/mesh/files/`; files of messages no longer kept are deleted); a bigger one shows **Download**, with the date it stays on the server until. A file gone from the server shows a card saying so.
- **Your own big files**: the sender keeps a copy of what it sends up to 250 MB; a bigger file is shown from where you picked it (moving or deleting it there breaks its preview on your side only).
- A notification for an image shows the image.

A file is encrypted on your computer before it leaves (AES-256-GCM, with a key of its own) and uploaded as an ntfy attachment under a random name; its key travels inside the message, sealed like any other: for everyone in the mesh, or for one person alone in a private conversation. The server stores ciphertext only, and the downloaded file is checked against the hash the sender gave. A desktop only downloads from its own mesh server's attachments: a message can't make it fetch anything else.

## Deleting a message

Hover a message and click its **bin**, then click again within 3 seconds to confirm.

- **Your own messages** are deleted **for everyone**: each desktop shows "This message was deleted" in its place, and drops its file, its notification (if still on screen) and its entry in the notification history. A desktop that was off does the same when it catches up, and so does someone who joins later and replays the conversation.
- **Someone else's messages** are deleted **on your computer only**.
- **Only the sender can delete a message for everyone.** Each message carries a commitment to a proof that only its sender's desktop can make (it comes from that desktop's private key), and deleting it shows the proof; a private conversation's deletion is sealed like its messages, which also proves who sent it. Messages to everyone sent before deleting existed have no commitment, so they can only be deleted on your computer.
- **What it can't undo**: someone who already read it has read it, the server keeps its encrypted copy (and a file's) until it expires, and a desktop changed to ignore deletions keeps the message. A message you wrote on another computer can only be deleted from that computer.

## Listening together

Share what your **YouTube Music** or **Spotify** plays in a conversation (everyone, or one person): the **headphones** button in the conversation's header (Listen together, music only). The **film** button next to it is Watch together, for Jellyfin (below). The others see "Khoa is sharing their music" with the song, and a notification with **Listen along**. Listening along opens the same song in their own player, at the same moment, and follows your pauses, seeks and next songs; the bar shows who listens and how far into the song (or film) the host is. **Stop** ends it (the session also ends when your player is gone for a minute); **Leave** stops listening along.

- **The other app**: a listener with Spotify follows a YouTube Music host, and the other way round. A Spotify song is found on YouTube Music by its title, artist and length (YouTube Music's own search), and played there. Spotify has no search without an account, so a YouTube Music song opens Spotify's search for the listener to pick.
- **Apps, not the browser**: only the YouTube Music and Spotify apps can be shared; YouTube Music's website in a browser tab tells no song id, so sharing says to play it in the app (on nixbook, `zenBrowserConfig.openInApps` sends music.youtube.com links from Zen to the app).
- **Which app**: an app already open (the host's, else the other), else one installed (the host's first), started for you on the song. YouTube Music songs always open in the YouTube Music app, never on its website in the browser.
- **You take over**: a listener who plays something else (for 3 seconds), or pauses (for 8 seconds), stops listening along (it says so in the Mesh tab). A song ending on the listener's side first (autoplay, the player stopping) waits for the host's next one instead, and a song YouTube Music plays under another id (its audio version for its music video, or the other way round) counts as the same song when the title and artist match. The song is opened once, the way a click on its link opens it in the YouTube Music app (through the app's Electron bridge: never the browser, nor its window raised), else through MPRIS; if 12 seconds later (or as soon as the app moves on to another song) the listener's app plays something else (that version isn't available to their account or country, and YouTube Music went on with its queue), another version of the same song by the same artist is opened instead, once; after that it waits for the next song ("This song doesn't play in your YouTube Music"). No retry loop. Closing the app while listening along stops listening along. The song opens at the host's position (`&t=` on the YouTube Music link, the position given to mpv for Jellyfin; Spotify can't, so it jumps there once it plays); the listener's player jumps to it only once it has opened and really plays, when the host seeks, pauses or resumes (2.5 s apart or more), and for a drift of more than 5 seconds at most every 30 seconds: some slack for a slow network, and each jump makes YouTube Music buffer again, which looks like a reload. A song ending first waits 30 seconds for the host's next one.
- **Privacy**: nothing is shared until you click the button, and only the song (title, artist, album, cover, length), the position and play/pause. A session with one person is sealed for them alone, like private messages. Nothing is kept.
- Each listener streams from their own account: everyone needs their own YouTube Music or Spotify.
- **Calling at the same time**: turn on [echo cancellation](./media.md#echo-cancellation) (the button in the bar while you share or listen along), so the music playing on your computer doesn't go back through your microphone.
- **When it ends**: a song, film or episode that ends (or is stopped) pauses the listeners where it stopped, and your bar says nothing is playing; the session stays open, and the next thing you play is shared.
- **Which player is shared**: of the button's kind (music, or Jellyfin), one that has something on it (playing first, then paused); if the one shared has nothing and another of that kind has, it moves to that one.

**Watching together (Jellyfin)**: the **film** button (shown where Jellyfin is installed) shares what this computer's mpv plays from Jellyfin (jellyfin-mpv-shim), and only that, even while music plays: the others get **Watch along**, which plays the same film or episode on their own mpv from the same moment, and follows your pauses, seeks and next episodes. Each one watches from their own Jellyfin account, signed in in **Settings > Services > Jellyfin** (their progress is theirs; also shown in Settings > Desktop agents). On the same server it is the same item; on another server it is found by its IMDb/TMDb/TVDb ids, else by name and year, or series, season and episode (`jellyfin-mcp listen-info` / `listen-play`). Audio and subtitles follow each one's own Jellyfin preferences. Signed in to [YouTube Music in the background](./media.md#youtube-music-in-the-background), listening along plays the song there, without a window. Listening and watching together use no AI: they work with the AI features off (`policies.ai` 0).

From the command line: `nixbook-shell ipc call mesh listenShare MEMBER` (music; "" = everyone), `watchShare MEMBER` (Jellyfin), `listenStop`, `listenJoin MEMBER`, `listenLeave`, `listenStatus`.

## Joining

**With an invite** (the usual way): Settings > General > Mesh, paste the invite code someone gave you (`nixbook-mesh-invite:…`), **Join**. That's all: the server, your account and the mesh's key come from the code, and your desktop makes its own access token. An invite works once.

**Your name** (same section) is what the others see: `login@hostname` by default (for example `khoa@totoro`). It is only a name: you stay the same member under it (your login). The conversation shows each member's current name, also on their earlier messages.

## Inviting people (the server's admin)

The server's admin (on nixbook: `khoa`, an ntfy admin set once in Vault) sees a **People** list in the same section: everyone in the mesh, with **Remove**, and a field to **Invite** someone by name (lower case). The invite code that appears holds the server, a one-time password for their new account and the mesh's key: send it privately. Inviting the same name again makes a new code (the old one stops working). **Remove** cuts that person off at once.

Nothing is configured on the server per person: the admin's desktop creates the account through ntfy's admin API (`/v1/users`, with `mesh-*` access), and the invited desktop changes the password and makes its token (`/v1/account/password`, `/v1/account/token`).

## Setting it up by hand

For the admin (and anyone with a token from the server's configuration): **Set it up by hand instead** shows the access token field (`tk_…`, **Save the token**, **Test**) and **Create a mesh** / **Join** with a mesh code (**Show the mesh code** shows it, `XXXXX-XXXXX-…`; a typo is refused). The admin starts like this: their token from Vault, then **Create a mesh**, then invites.

The token and the mesh key are kept in your keyring (GNOME Keyring, `service=nixbook-mesh`). Without a keyring, or with `NIXBOOK_MESH_STORE=file`, they are kept in `~/.config/nixbook-shell/mesh/token` and `key` (0600), which can also be written by hand. They are never in the Nix configuration. The server (`mesh.server`) is set by nixbook: `https://ntfy.rpcu.io`, on the RPCU production cluster (`../atlas`, `clusters/production/ntfy`).

The same section turns off sharing your status (the others then see "Not sharing their status"), the notifications, or the whole mesh.

## Security

- Everything a desktop sends is encrypted with AES-256-GCM, with the mesh's key, before it leaves the computer. The server only stores and passes on ciphertext, on a topic whose name is derived from the key, so it doesn't say who is talking either.
- **Private messages are for their recipient alone.** Each desktop has its own key pair (X25519, the private half in your keyring). A message (or read receipt) to one person leaves in a sealed envelope: one copy for their key and one for yours, sealed with a one-off key, with nothing on the outside (no sender, no recipient, no time; the length padded to steps of 256 bytes). The other members, who hold the mesh key, can't open it, and neither can the server's admin; they can't even tell who wrote to whom, only that a private message passed, and when. Inside, the sender's own key proves who wrote it. The server's admin could still tell from the server's logs which account posted an envelope, never to whom or what. On each desktop the conversation is kept unencrypted in your home folder, like any chat app's.
- **Keys are pinned.** Your desktop keeps the first key it sees for each person. If it changes (a new computer, or someone posing as them), private messages from and to them are held back, and their conversation says so with **Trust the new key**. Each private conversation shows the other person's key fingerprint, and Settings shows yours: compare them to be sure.
- Messages to everyone are sealed with the mesh key only: every member reads them.
- Each person has their own account and token on the server: **Remove** cuts one person off at once. To also keep them out of what they might have recorded, create a new mesh and invite the others again.
- An invite code holds the mesh's key: send it privately. It can be used once.
- The desktop agents (DAI, any agent using the desktop tools) can't use the `mesh` IPC target: they would speak in your name.

## From the command line

`nixbook-mesh` does the work (`nixbook-shell/scripts/mesh.py`); the shell drives it:

| Command                                   |                                               |
| ----------------------------------------- | --------------------------------------------- |
| `nixbook-mesh status`                     | what is set (token, key, where they are kept) |
| `nixbook-mesh token set` / `token forget` | the access token (on stdin)                   |
| `nixbook-mesh mesh create` / `mesh code`  | a new mesh / its code again                   |
| `nixbook-mesh mesh join` / `mesh leave`   | enter a code (on stdin) / forget the key      |
| `nixbook-mesh test SERVER`                | the token works, the mesh is reachable        |
| `nixbook-mesh limits SERVER`              | the largest file the server takes, its expiry |
| `nixbook-mesh sendfile SERVER`            | send a file (`{path, to, text}` on stdin)     |
| `nixbook-mesh fetch SERVER`               | download a received file (`{file}` on stdin)  |
| `nixbook-mesh match`                      | a Spotify song on YouTube Music (on stdin)    |

And the shell's IPC target `mesh`: `nixbook-shell ipc call mesh status`, `send TEXT`, `sendTo MEMBER TEXT`, `sendFile PATH`, `sendFileTo MEMBER PATH`, `open`, `openConversation MEMBER`.

The conversation is kept in `~/.local/state/quickshell/user/mesh-conversation.json` (the last 500 messages).
