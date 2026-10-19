# Google Keep sync of the notes

The shell's **notes** (the desktop widget's notes and the **Notes** window) can be synced with **Google Keep**: what you write here goes there, and what you write there comes back.

Google has no public Keep API (only for Workspace), so the sync goes through [gkeepapi](https://github.com/kiwiz/gkeepapi), the unofficial client, which the shell packages as `nixbook-keep` (`nixbook-shell/keep.nix`).

## Connect an account

Open the **Notes** window and click **Keep** (next to **New**).

Google Keep's client needs a **master token**: a token with full access to your Google account, to be kept like a password. [gpsoauth's alternative flow](https://github.com/simon-weber/gpsoauth#alternative-flow) explains how to get one; the panel's **How to get a master token** button opens that page.

Give the panel your account's email and the token, then **Connect**. They are kept in the keyring (GNOME Keyring, through `secret-tool`), never in the notes file nor in the settings, and are checked against Keep right away: a refused token says so at once. **Disconnect** forgets them; your notes stay.

::: warning
A master token gives full access to your Google account. Anyone who has it can read your mail and your Drive: keep it as you would your password, and revoke it when you don't use it any more.
:::

## The sync

**Sync now** in the panel syncs at once. The shell also syncs on its own every `keep.refreshMinutes` (15 by default) when `keep.enable` is on, and shows what the last sync did: the notes sent to Keep, the notes that came from it, the notes updated on either side, and the conflicts.

From a terminal: `nixbook-shell ipc call keep status` (the account, the last sync) and `nixbook-shell ipc call keep sync`.

## How a note maps to a Keep note

| The shell                               | Keep                 |
| --------------------------------------- | -------------------- |
| The first line of the note              | The note's title     |
| The other lines                         | The note's text      |
| A note whose lines are all `- [ ] item` | A list (a checklist) |
| The pin                                 | The pin              |

The other way round: a Keep note's title and text become the note's lines, a Keep list becomes a checklist, and Keep's pin becomes the pin.

## Which side wins

Each note remembers its Keep note and when the two were last in sync, so the shell knows what changed where:

- a note changed in the shell is pushed to Keep;
- a note changed in Keep comes back;
- when both changed, the newer one wins (the count of those is in the panel's summary).

**Deletions are not synced.** A note deleted in the shell stays in Keep, a note deleted in Keep stays in the shell, and neither is brought back: the sync never resurrects a note you removed on purpose. The Keep notes whose shell note is gone are remembered, so they don't come back at the next sync either.

## The settings

**Settings → General → Google Keep**:

- `keep.enable` — the sync on its own (on demand it always works);
- `keep.refreshMinutes` — how often it runs (15 minutes);
- `keep.push` — the shell's new notes go to Keep;
- `keep.pull` — Keep's new notes come in.

In Nix, they are `programs.nixbook-shell.settings.keep.*`:

```nix
programs.nixbook-shell.settings.keep = {
  enable = true;
  refreshMinutes = 30;
  push = true;
  pull = true;
};
```

A key set in Nix is locked in the Settings window.

## What is not synced

Keep's **colours**, **labels**, **drawings**, **images** and **recordings** are not: gkeepapi does not read or write them. The shell's own **attachments** (the files of a note) stay on this computer. Trashed Keep notes are not imported.
