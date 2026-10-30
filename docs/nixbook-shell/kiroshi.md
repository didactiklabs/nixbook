# Kiroshi scan

`Mod+K` turns the screen into a brief, so you don't have to read everything to know what needs you. DAI looks at the focused screen together with what you are doing (the focused window and what a screen reader sees in it, your open and recent windows, the latest notifications, your next events) and shows, over the screen:

- **Focus** and **Doing** at the top: the one thing that matters now, and what you are in the middle of.
- **What matters, framed on the screen**, coloured by urgency (now, soon, later, noise dimmed), each with a one-line gist and its best offer. The items worth acting on come first (the offers' value × urgency).
- **Open an item** (click it, or press its number) for the substance: the **facts** as bullets (who, what, when or the deadline, the numbers, links, what is asked of you), **why** it matters now and the **next** step if you do it yourself.
- Then up to three **offers** (`A`, `B`, `C`, best first), each with the effort it saves (`~2 min · 6 clicks`). The scan only offers what saves real work: a reply drafted with the right context, a date in a message added to your calendar, a request filed as a task with its due date, an error's cause and fix, a long thread summed up with its action items in a note, a follow-up reminder, information gathered across apps, several routine notifications cleared at once. It never offers to open, focus or scroll to what is already on screen, dismiss one toast, play or pause, or "keep" what is already going on; when nothing is worth it, the card says so.
  - A **one-step offer** is a single action (a calendar event, a task, a reminder, a desktop note, text for the clipboard, a page opened in Zen, a notification's button or reply, notifications cleared), its arguments checked before it is shown; it runs at once and shows ✓ or the error in the card. The desktop tools obey [desktop control](./desktop-agents)'s pause and guards; the notifications' own actions are done by the shell.
  - One that **sends** something (a reply) shows its draft, editable, and waits for **Send** (`Enter`): nothing is sent without that click.
  - A **bigger offer** shows its plan and, when it writes something, the **draft, editable**; it goes to DAI in a new conversation of its speech bubble, which carries it out with the desktop tools.
  - `Enter` takes the chosen offer (the best one unless you picked another). **Copy draft**, or **Tell me more**: DAI gets that part of the screen and explains it in the bubble.
- **It learns what you take**: each offer you use is remembered, and the next scans are told the last ten, so they offer more of what you actually use.
- **Handle the routine ones** does every routine item that has an offer worth it and needing no confirmation in one go (one-step offers run in place, the others go to DAI together).

The brief shows in about 2 seconds, the framed items in about 5, and every item's details in under 10; `Esc` closes an item, then the scan. `Mod+K` again while it is open closes it.

## What it needs

Claude Code, logged in once (the same as [DAI in the side panel](./ai-assistant#dai-in-the-side-panel)), and AI switched on (**Settings → Desktop agents → AI features**). It runs on Claude with vision through Claude Code, Sonnet by default (`kiroshiModel` in `~/.config/nixbook-shell/desktop-mcp.json`). The screenshot and the context go to Claude; the text goes through the [privacy mask](./desktop-agents) like every other AI pass, and is listed in the sent log.

From a script: `nixbook-shell ipc call kiroshi scan` (again: close), `status` (the brief and the items as JSON), `expand N`, `option N M`, `tellMore N`, `handleRoutine`, `close`. An offer that sends something still waits for the Send click in the card: it is never sent from IPC.

The scan came from [nixbook-meta](https://github.com/Banh-Canh/nixbook-meta), where it runs on Meta's models.
