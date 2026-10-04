# Notifications

nixbook-shell is the session's notification server. Popups appear at the top of the screen (one card per notification by default, so messages from different people in one app don't merge — `notifications.splitPopups`), and the **right sidebar** (Mod+N) holds the notification centre.

## Acting on notifications

- **Left click** runs the notification's default action (opens the conversation…), **right click** hides the popup, **middle click** discards it.
- Hovering pauses the timeout; nixbook keeps popups on screen for 15 s.
- **Mark as read** hides the popup but keeps it in the centre, and triggers the app's own mark-as-read action when it has one.
- **Delete** discards it.
- **Reply**: apps that support inline replies get a reply box in the card (Enter sends, Esc cancels); otherwise _Reply_ runs the app's reply action or opens the conversation.
- Notifications are grouped and expandable to show every message.

## Keep on screen

`notifications.persistent` keeps matching popups until you dismiss them — useful for chat apps. nixbook keeps Vesktop and notifications mentioning Discord, Slack, WhatsApp, Instagram, Facebook or Messenger in their app name or title.

## Cut-ins

Important notifications get the theme's **full-screen cut-in**: the Persona dialogue box with the message typed out, the Chiikawa character popping up with a speech bubble, a Cyberpunk holocall glitching in, or a Ghibli card drifting in on a gust of wind. Click for the default action; Esc, Enter or Space dismiss; you can **reply** from the cut-in.

Which notifications cut in is configured in **Settings → Bar → Notifications → Cut-ins** (`notifications.cutIn`): critical urgency, chosen apps, and **rules**:

| Rule syntax               | Matches                                                         |
| ------------------------- | --------------------------------------------------------------- |
| `word`                    | The word anywhere (app name, title, text, hints)                |
| `"word"`                  | The whole word                                                  |
| `a + b`                   | Both                                                            |
| `!x`                      | `x` absent                                                      |
| `app:`, `title:`, `body:` | One field                                                       |
| `last:`                   | The last sender's messages                                      |
| `line:`                   | The body's last line (the newest message of a re-posted thread) |
| `hint:`                   | The notification's hints (e.g. `hint:calendar.google.com`)      |

A **blacklist** of rules vetoes cut-ins (nixbook skips the echo of your own replies). The settings page has a live tester showing which rule decided for the latest notifications; from a terminal:

```bash
nixbook-shell ipc call personaCutIn test "Name" "Message"   # preview
nixbook-shell ipc call personaCutIn explain                 # why the last one did or didn't cut in
```

## Quiet rules

`notifications.quiet` (Settings → Bar → Notifications → Quiet) keeps matching notifications out of popups, cut-ins and the chime — they still reach the centre and history. nixbook quiets the copies of calendar reminders that the phone (via KDE Connect) and the browser also send, so only DankCalendar's reminder pops up.

## Duplicates

`notifications.deduplicate` drops copies: a notification **relayed from your phone** (KDE Connect, GSConnect) of a message a desktop app already showed — within 30 minutes by default, matched strictly on the message — is expired unseen, or replaced by the desktop one if it came first. Bursts of the same app, title and text within 2 seconds are dropped too, and a thread re-posted with new lines replaces the old popup. Each message is logged once in the history.

## History

Every notification is kept in a **history** (`notifications.history`, 30 days by default, 0 = forever), even after you dismiss it from the centre: the centre's history button shows it with search, day headers and per-entry delete, plus "older than 7 / 30 days" and "delete all". The same controls and the retention are in Settings → Bar → Notifications → History.

```bash
nixbook-shell ipc call notificationHistory count
nixbook-shell ipc call notificationHistory deleteOlderThan 7
```

AI coding workspaces can read it with the [`notification-history` ocm module](/user/ai-workspaces#modules-for-workspaces), and desktop agents with their `notifications` tool.

## Do Not Disturb

Do Not Disturb (a quick toggle) silences popups and sounds, including calendar reminders.
