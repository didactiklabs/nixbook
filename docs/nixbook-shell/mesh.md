# Mesh

The mesh lets a few people talk desktop to desktop over the internet: messages to everyone or to one person, and everyone's status. No desktop connects to another directly: they all go through an [ntfy](https://ntfy.sh) server, and nothing they send can be read there.

## What it does

- **Messages** to everyone, or to one person. They are written in the right sidebar's **Mesh** tab (Mod+N), which lists the conversations (Everyone, then each person), with quick messages ("❤️", "Thinking of you", "On my way"…, `mesh.quickMessages`).
- **Status**: free, in a meeting, gaming, busy (a fullscreen window), do not disturb, away (locked, screens off). It never says which app or window. It is sent when it changes, and again every 10 minutes; someone not heard from for 25 minutes shows as offline.
- **Read receipts** in a conversation with one person ("seen").
- **Notifications**: each message arrives as a notification named after its sender, with **Reply**, which opens the conversation. On nixbook, a message to you alone gets the Persona cut-in, and every mesh message stays on screen like other chats (`hint:"nixbook-mesh-direct"`, `nixbook-mesh` in the notification rules).
- **The bar's mesh widget**: how many people are around, and unread messages. Hovering it lists everyone's status; a click opens the conversation that has something new.

Messages written while the computer was off arrive when it comes back (the server keeps them 72 hours). Messages older than two hours then count as unread, without a notification each.

## Setting it up

In **Settings > General > Mesh**:

1. **Server**: nixbook sets `https://ntfy.rpcu.io`, the server on the RPCU production cluster (`../atlas`, `clusters/production/ntfy`).
2. **Your name**: what the others see (your login, capitalised, by default).
3. **Access token**: paste the `tk_…` token the server's admin gave you, then **Save the token**. **Test** checks it.
4. One person clicks **Create a mesh**. **Show the mesh code** shows its code (`XXXXX-XXXXX-…`), which the others type or paste and **Join**. The code is checked as it is entered: a typo is refused.

The token and the mesh key are kept in your keyring (GNOME Keyring, `service=nixbook-mesh`). Without a keyring, or with `NIXBOOK_MESH_STORE=file`, they are kept in `~/.config/nixbook-shell/mesh/token` and `key` (0600), which can also be written by hand. They are never in the Nix configuration.

The same section turns off sharing your status (the others then see "Not sharing their status"), the notifications, or the whole mesh.

## Security

- Everything a desktop sends is encrypted with AES-256-GCM, with the mesh's key, before it leaves the computer. The server only stores and passes on ciphertext, on a topic whose name is derived from the key, so it doesn't say who is talking either.
- **Every member holds the same key.** A message to one person is shown only to them, but the others could read it with the key: the mesh is meant for people who trust each other. Per-person keys aren't implemented.
- Each person has their own access token on the server. Removing it there cuts that person off at once. To also keep them out of what they might have recorded, create a new mesh and give its code to the others.

## Adding someone

On the server (the RPCU production cluster, `../atlas`):

1. In Vault, `secrets-production/ntfy/config`: add `name:<hash>:user` to `AUTH_USERS` (the hash from `ntfy user hash`) and `name:tk_<29 letters or digits>:label` to `AUTH_TOKENS`.
2. In `clusters/production/ntfy/cm.yaml`, `auth-access`: add `"name:mesh-*:rw"`.

On their desktop: the token in Settings, then the mesh code that any member can show.

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
