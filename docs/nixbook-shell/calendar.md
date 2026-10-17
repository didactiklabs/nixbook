# Calendar & tasks

nixbook-shell's calendars, reminders and to-do lists come from your [accounts](./accounts) (Google, iCloud, Fastmail, Nextcloud or any CalDAV server), through its own backend, `nixbook-accounts`. Several accounts show together; without any, everything is kept on this computer ([This computer](./accounts#without-sync-this-computer)).

## Connect an account

Every calendar widget has the same button: it opens the Calendar window; right-click syncs now. Accounts are added from the [accounts window](./accounts#add-an-account) (the Calendar window's account button, or `nixbook-shell ipc call accounts launch`).

## The Calendar window

Open it from the launcher (**Calendar**), a click on the bar clock or on a day of the desktop calendar, a calendar widget's button, or `nixbook-shell ipc call calendar launch` (`open YYYY-MM-DD` for a day).

- **The month** on the left: each day's events (all-day ones as bars), today circled, "+N more" when a day is full. A click selects the day, a double-click adds an event on it. **Today** (T), the arrows (Page Up/Down), **Sync** (F5), **New** (Ctrl+N).
- **The selected day** on the right: its events with their time, place and calendar, and **Join** for a meeting.
- **An event** opens in the editor: title, all day, start and end (a date picker and the time), calendar (several accounts: which one), repeat (daily, weekdays, weekly, monthly, yearly), reminders (none, at the start, 5, 10, 30 minutes, 1 hour, 1 day before; or the calendar's own), place or meeting link, notes. For a recurring event, choose **This event** or **All events**: changing all of them from one occurrence moves every occurrence the way that one moved. **Delete** asks first. Events of a read-only calendar (holidays, someone's shared calendar) open without editing.

- **Calendars shown** (the eye button): every calendar of every account, Google's subscribed calendars included (holidays, birthdays, a colleague's), each with a switch. A calendar turned off has its events hidden everywhere (the window, the widgets, the next events) and no reminders, and Google's aren't fetched any more. Each starts as in Google Calendar (unticked or hidden there: off); your choice is kept on this computer and Google Calendar's own selection doesn't change. New events go to a shown calendar.

Changes go to the event's account at once. The shell syncs every `calendar.refreshMinutes` (30), and on demand.

## Where events show up

- **Calendars**: dots on the days of the sidebar, desktop and bar-clock calendars. Clicking a day in the sidebar lists its events, with an _add event_ button.
- **Next events**: the bar clock popup lists them, and so do:
  - the **Next Event** bar widget — "in 12 min" and the title, the following ones on hover; click **joins the meeting** when it starts within 10 minutes, otherwise opens the Calendar window;
  - the **Next Event** desktop widget — the next event large with a _Join_ button, and the three after it.

## Tasks

The **to-do list** — in the sidebar, as a desktop widget, in the bar clock popup, and from the launcher's _add task_ — is your accounts' task lists: Google Tasks, the to-do lists of a CalDAV server such as iCloud's Reminders, and those kept on [this computer](./accounts#without-sync-this-computer). The **Tasks** window shows each list as a column, subtasks under their parent, and a _Deadlines_ column.

## Reminders

Reminders are the shell's own notifications (app **Calendar**): one at each reminder time of an event (its own reminders, else its calendar's, as set in Google Calendar or on the server), with **Join** (a meeting link), **Snooze** (5 minutes) and **Open** (the Calendar window on that day). They stay until handled and are silenced by Do Not Disturb; the Persona theme shows them as a cut-in (rule `app:^"Calendar"`). A reminder missed while the shell wasn't running still shows if it is at most 10 minutes late. Copies of the same reminder from your phone or browser can be [quieted](./notifications#quiet-rules).

## Ask the assistant

The [config assistant](./ai-assistant) answers questions such as "how do I sync my Google calendar?", and desktop agents read and change your calendar through the [`calendar` tool](./desktop-agents#what-agents-can-do): the next events, a day, the calendars, creating, changing and deleting events (they ask you before deleting), and turning calendars on or off ("hide the holidays").
