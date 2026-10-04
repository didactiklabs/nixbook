# Calendar & tasks

[DankCalendar](https://github.com/AvengeMedia/dankcalendar) (`dcal`) is part of nixbook-shell: it is on the shell's PATH and its daemon runs as the `dcal` user service. It syncs your accounts and keeps every calendar surface of the shell in sync.

## Connect an account

Every calendar widget has the same account button: **"Connect a Google account"** until one is connected — your browser opens Google's login (dcal ships its own OAuth client: no Google Cloud project needed) — then **"Open DankCalendar"**, where you add other accounts: **Microsoft**, **CalDAV**, **iCloud** and **iCal feeds**. Right-click syncs now.

## Where events show up

- **Calendars**: dots on the days of the sidebar, desktop and bar-clock calendars. Clicking a day in the sidebar lists its events, with an _add event_ button. Clicking the bar clock (right-click: sync) or a day of the desktop calendar opens DankCalendar.
- **Next events**: the bar clock popup lists them, and so do:
  - the **Next Event** bar widget — "in 12 min" and the title, the following ones on hover; click **joins the meeting** when it starts within 10 minutes, otherwise opens DankCalendar;
  - the **Next Event** desktop widget — the next event large with a _Join_ button, and the three after it.
- Events are re-read every `calendar.refreshMinutes` (30); the refresh button in the sidebar calendar syncs immediately.

## Tasks

The **to-do list** — in the sidebar, as a desktop widget, in the bar clock popup, and from the launcher's _add task_ — is your account's task list (Google Tasks…) once one is connected, and a local list before that.

## Reminders

Reminders are DankCalendar's own notifications, at the event's reminder times (or 10 minutes before), with **Join**, **Open**, **Snooze** and **Dismiss** actions. They are shown by the shell and silenced by Do Not Disturb. Copies of the same reminder from your phone or browser can be [quieted](./notifications#quiet-rules).

## Ask the assistant

The [config assistant](./ai-assistant) answers questions such as "how do I sync my Google calendar?", and desktop agents can read your calendar (read-only) through the [`calendar` tool](./desktop-agents#what-agents-can-do).
