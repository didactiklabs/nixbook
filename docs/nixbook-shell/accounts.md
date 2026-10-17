# Accounts, contacts, tasks & calendar

nixbook-shell has its own accounts backend, **`nixbook-accounts`** (`nixbook-shell/accounts/`, Go). Add your accounts once; their **contacts**, **tasks** and **[calendars](./calendar)** show together in the shell. **Google** and **CalDAV/CardDAV** servers (iCloud, Fastmail, Nextcloud, or any other) are supported.

## Without sync: this computer

You don't need any account: the built-in **This computer** account is always there, and keeps contacts, task lists and calendars on this computer only (`~/.local/share/nixbook-accounts/local/`: the data itself, include it in your backups). It has a first task list (_Tasks_) and a first calendar (_Personal_, a 10-minute reminder by default), and does everything the others do: labels, subtasks, recurring events, reminders. When you add a synced account, new contacts, tasks and events go to it by default, and those already on this computer stay there (pick an account in the editors to choose). It can't be removed.

The shell's former local to-do list (`todo.json`) is moved into it the first time, its lists included; the old files are kept as `todo.json.bak` and `todo-lists.json.bak`.

## Add an account

Open the accounts window from the Contacts window, the Tasks window (**Accounts**), a to-do widget's account button (right click), or `nixbook-shell ipc call accounts show`.

### Google

`nixbook-accounts` signs in to Google with **your own Google Cloud app**: DankCalendar's built-in client is licensed only for DankCalendar, and it can't read contacts. You make the app once, in about five minutes; every Google account you add uses it. The window walks you through it:

1. In [Google Cloud](https://console.cloud.google.com/apis/credentials), create a project and enable the **People API** and the **Tasks API** (and the **Calendar API**, for later).
2. **Google Auth Platform → Branding**: an app name and your email. **Audience**: _External_, then **Publish** the app. An app left in _Testing_ is signed out every 7 days. Google says the published app is unverified: that's fine, it's yours.
3. **Clients → Create client → Desktop app**, and download its JSON (`client_secret_….json`).
4. In the accounts window, **Use the downloaded file** (it picks the newest one in `~/Downloads`), or enter the ID and secret.
5. Your browser opens Google's sign-in; once you accept, the account's contacts and tasks sync.

Add another Google account the same way (**Add**). Signing in with an account already added signs it in again (for example after Google signed it out). **Remove** takes an account's contacts and tasks out of the shell; they stay in the account.

The app's client and your accounts' tokens are kept in the keyring (GNOME Keyring, through `secret-tool`). From a terminal: `nixbook-accounts setup google --find`, `nixbook-accounts add google`, `nixbook-accounts status`, `nixbook-accounts remove <account>`.

### iCloud, Fastmail, Nextcloud or another server

Pick the server in the window's second card, then give your user name and a password. **iCloud** and **Fastmail** need an **app password**, not your account's: the window's **Make an app password** button opens the page where you make one. **Nextcloud** and other servers need their address too. The account is checked on its server when you add it (a refused password says so), and its address books and the calendars that hold to-dos are found by themselves.

- Contacts come from every address book (new ones go to the first). Labels are the contacts' categories; the star is the "Starred" category.
- Task lists are the calendars that hold to-dos (iCloud's Reminders lists, for example). New lists are made as to-do calendars.
- Calendars are the ones that hold events; a recurring event's changed or cancelled occurrences are kept as the server does (RECURRENCE-ID, EXDATE).

The password is kept in the keyring. From a terminal: `echo 'app-password' | nixbook-accounts add dav --preset icloud --username you@icloud.com --password-stdin` (`--preset fastmail`, `nextcloud --url cloud.example.org`, or `custom --url https://dav.example.org`).

## The Contacts window

Open it from the launcher (**Contacts**), the contacts widget, or `nixbook-shell ipc call contacts show` (`open <id>` for one contact).

- **On the left**: search (names, emails, companies, notes, labels; accents ignored; phone numbers by their digits), the **All / Starred / account / label** chips (accounts and the label's account appear when you have several), then starred contacts and the rest from A to Z.
- **On the right**: the selected contact, and its account when you have several. A click on an email writes, on a phone calls (`tel:`, e.g. through KDE Connect), on an address opens the map; the copy button copies it. **Email**, **Call** and **Message** buttons, the birthday with the age it turns, labels, notes.
- **Edit** (Ctrl+E) or **New** (Ctrl+N): names, company and job title, emails, phones, addresses, birthday (`YYYY-MM-DD` or `MM-DD`), websites, labels (a new label is made on save), notes, starred; a new contact goes to the account you pick. Save (Ctrl+S) sends the account only what changed; the rest of the contact, including fields the window doesn't show, stays as it is.
- **Delete** asks first; Google keeps deleted contacts in its Trash for 30 days, other servers delete them.
- Ctrl+F searches, F5 syncs. A narrow window shows the list, then the contact.

Contacts sync when the window opens, every 30 minutes, and on demand (the sync button). Only the changes since the last sync are fetched. Edits go to the contact's account first; its answer lands in the local copy (`~/.local/state/nixbook-accounts/contacts.json`), which the window and the widget watch, so changes from anywhere, an agent included, show at once.

## Tasks

The to-do list, the [Tasks window](./calendar#tasks) and the to-do widgets show every account's task lists; with several accounts a list's name says its account (_My Tasks · work_). Tasks move between the lists of one account. They sync at start, every 10 minutes, when the Tasks window opens, and from a to-do widget's account button.

## The contacts widget

A desktop widget (desktop right-click → **Widgets → Contacts**, or Settings → Background): the **birthdays of the next two weeks** ("Today", "Tomorrow", the age turned), then your **starred contacts**. A contact opens the window on them. The button syncs, or opens the accounts window to add one.

## For AI agents

Desktop agents manage contacts with the [`contacts` tool](./desktop-agents#what-agents-can-do): search and read them, create them in an account, update, star, label and delete them (deleting: they ask you first), manage labels, sync, open the window on a contact, and batch up to 50 changes, for example to clean up or label many contacts at once. Tasks go through the `tasks` tool.
