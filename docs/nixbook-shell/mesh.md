# Mesh

The mesh lets a few people talk desktop to desktop over the internet: messages to everyone or to one person, and everyone's status. No desktop connects to another directly: they all go through an [ntfy](https://ntfy.sh) server, and nothing they send can be read there.

## What it does

- **Messages** to everyone, or to one person. They are written in the right sidebar's **Mesh** tab (Mod+N), which lists the conversations (Everyone, then each person), with quick messages ("❤️", "Thinking of you", "On my way"…, `mesh.quickMessages`).
- **Status**: free, in a meeting, gaming, busy (a fullscreen window), do not disturb, away (locked, screens off). It never says which app or window. It is sent when it changes, and again every 10 minutes; someone not heard from for 25 minutes shows as offline. How the others see you shows at the top of the Mesh tab ("You (Khoa): Free") and first in the bar widget's hover list. In order: not shared (the switch is off), away, do not disturb, in a meeting (a timed calendar event now), gaming (a Steam game or gamescope focused), busy (a fullscreen window), free.
- **Read receipts** in a conversation with one person ("seen").
- **Notifications**: each message arrives as a notification named after its sender, with **Reply**, which opens the conversation. On nixbook, a message to you alone gets the Persona cut-in, and every mesh message stays on screen like other chats (`hint:"nixbook-mesh-direct"`, `nixbook-mesh` in the notification rules).
- **The bar's mesh widget**: how many people are around, and unread messages. Hovering it lists everyone's status; a click opens the conversation that has something new.

**History**: each desktop keeps its last 500 messages (`~/.local/state/quickshell/user/mesh-conversation.json`): scroll up in a conversation. The server keeps messages 3 months, so a desktop that was off catches up, and one that joins (or is reinstalled) gets the conversation so far, without others' private messages. Status updates older than 30 minutes are skipped when catching up. Two computers of the same person don't share their history.

Messages written while the computer was off arrive when it comes back (the server keeps them 3 months: `cache-duration` in `../atlas`). Messages older than two hours then count as unread, without a notification each.

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
- **Every member holds the same key.** A message to one person is shown only to them, but the others could read it with the key: the mesh is meant for people who trust each other. Per-person keys aren't implemented.
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

And the shell's IPC target `mesh`: `nixbook-shell ipc call mesh status`, `send TEXT`, `sendTo MEMBER TEXT`, `open`, `openConversation MEMBER`.

The conversation is kept in `~/.local/state/quickshell/user/mesh-conversation.json` (the last 500 messages).
