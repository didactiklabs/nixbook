# Mesh

The mesh lets a few people talk desktop to desktop over the internet: messages to everyone or to one person, and everyone's status. No desktop connects to another directly: they all go through an [ntfy](https://ntfy.sh) server, and nothing they send can be read there.

## What it does

- **Messages** to everyone, or to one person, with files. They are written in the right sidebar's **Mesh** tab (Mod+N), which lists the conversations (Everyone, then each person), with quick messages ("❤️", "Thinking of you", "On my way"…, `mesh.quickMessages`).
- **Status**: free, in a meeting, gaming, busy (a fullscreen window), do not disturb, away (locked, screens off). It never says which app or window. It is sent when it changes, and again every 10 minutes; someone not heard from for 25 minutes shows as offline. How the others see you shows at the top of the Mesh tab ("You (Khoa): Free") and first in the bar widget's hover list. In order: not shared (the switch is off), away, do not disturb, in a meeting (a timed calendar event now), gaming (a Steam game or gamescope focused), busy (a fullscreen window), free.
- **Files**: images and GIFs, shown in the conversation, and any other file (a PDF, an archive…), shown as a card. See [Files](#files).
- **Read receipts** in a conversation with one person ("seen").
- **Notifications**: each message arrives as a notification named after its sender, with **Reply**, which opens the conversation. On nixbook, a message to you alone gets the Persona cut-in, and every mesh message stays on screen like other chats (`hint:"nixbook-mesh-direct"`, `nixbook-mesh` in the notification rules).
- **The bar's mesh widget**: how many people are around, and unread messages. Hovering it lists everyone's status; a click opens the conversation that has something new.

**History**: each desktop keeps its last 500 messages (`~/.local/state/quickshell/user/mesh-conversation.json`): scroll up in a conversation. The server keeps messages a year, so a desktop that was off catches up, and one that joins (or is reinstalled) gets the conversation so far, without others' private messages. Status updates older than 30 minutes are skipped when catching up. Two computers of the same person don't share their history.

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

## Joining

**With an invite** (the usual way): Settings > General > Mesh, paste the invite code someone gave you (`nixbook-mesh-invite:…`), **Join**. That's all: the server, your account and the mesh's key come from the code, and your desktop makes its own access token. An invite works once.

**Your name** (same section) is what the others see: your login, capitalised, by default.

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

And the shell's IPC target `mesh`: `nixbook-shell ipc call mesh status`, `send TEXT`, `sendTo MEMBER TEXT`, `sendFile PATH`, `sendFileTo MEMBER PATH`, `open`, `openConversation MEMBER`.

The conversation is kept in `~/.local/state/quickshell/user/mesh-conversation.json` (the last 500 messages).
