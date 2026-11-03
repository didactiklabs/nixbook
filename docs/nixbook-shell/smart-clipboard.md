# Smart clipboard

Copy something and the right action shows at once (`ai.clipboard`, on by
default; **Settings → Desktop agents → Talk → Smart clipboard**): a small card
at the top left, beside V's speech bubble, for about 8 seconds, "Copied a
tracking number — **Track it** · Not now". It never takes the keyboard; click a
chip, or press `Mod+Alt+V` for the first one. Hovering it holds it.

What was copied is read on this computer in plain code, in well under a
millisecond (`src/modules/common/functions/clipboard_kinds.js`), in English,
French, German and Vietnamese:

| Copied                                                                                                  | Chips (best first)                         |
| ------------------------------------------------------------------------------------------------------- | ------------------------------------------ |
| A tracking number: UPS, FedEx, DHL, La Poste, Colissimo, Chronopost, any UPU number (check digits read) | Track it (the carrier's page)              |
| An address (`12 rue de Rivoli, 75001 Paris`, `Hauptstraße 5, 10115 Berlin`, `12 đường Lê Lợi, quận 1…`) | Directions, Show on the map                |
| A date or a time: "next Tuesday 3pm", "le 12 novembre à 14h", "morgen um 9 Uhr", "3 giờ chiều ngày mai" | Add to calendar                            |
| Text in another language than yours (stopwords and scripts)                                             | ✦ Translate (✦ Summarize when long)        |
| An error or a stack trace                                                                               | ✦ Explain it, ✦ Fix it                     |
| A link                                                                                                  | ✦ Summarize the page, Open                 |
| A phone number                                                                                          | Call / Text from the phone (KDE Connect)   |
| An e-mail address                                                                                       | Write to … (your mail app)                 |
| A long paragraph                                                                                        | ✦ Summarize, ✦ Rewrite                     |
| Code, a shell command                                                                                   | ✦ Explain                                  |
| An amount with a currency (`$1,299.99`, `49,99 €`, `500.000 ₫`)                                         | Convert to your currency (a search opened) |

Plain chips run at once. **Add to calendar** opens the Calendar's editor filled
in (title, date and time, the place when the text has an address): you check
it and save. A time said in another time zone ("Nov 4th at 9:00 PM ET",
"15:00 CET", "10h UTC+7", "3pm Pacific Time") is put in your local time; the
chip shows both, e.g. "Thu 5 Nov, 03:00 (9:00 PM ET)".

The ✦ chips are AI: each is an order for V in a new conversation of its speech
bubble (as [Kiroshi](./kiroshi)'s offers), answered there — Translate, Explain,
Summarize and Rewrite answer from the text alone; Fix it and Summarize the page
may use the desktop tools (the terminal's output, the page tools). They need
Claude Code logged in and AI switched on. The copied text is quoted as data,
goes through the [privacy mask](./desktop-agents) like every message, and the
chips show real names. A copied error is offered here, not also by **Help with
an error I copy**.

**Never** what a password manager copied (marked as such, or copied while one
is in front), never a password, a one-time code, a key or token, a card number
or an IBAN: nothing is shown and nothing leaves. Nor an agent's paste. With
`policies.ai` set to local only, the plain chips only; off, nothing. Not while
locked; quiet in Do Not Disturb, a meeting or a fullscreen app (no chip): the
clipboard history (`Mod+Q`) still has the plain action for each entry.

It learns lightly: a kind you ignore 5 times in a row (Not now, or letting it
fade) is no longer offered until **Offer them again**; the kinds and chips you
take come first. Each kind has its switch (`ai.clipboard.kinds.<kind>`);
`ai.clipboard.knownLanguages` (e.g. `["en"]`) are languages you read and don't
need translated, `ai.clipboard.currency` the one amounts convert to (empty:
from your language). State in `$XDG_STATE_HOME/nixbook-shell/smart-clipboard.json`.

`nixbook-shell ipc call smartClipboard status|classify TEXT|offer TEXT|run|runChip N|dismiss|reset`
(`classify` shows what a text is with no side effect; `offer` shows its chips
as if just copied, for demos). Agents can't: `smartClipboard` is in
desktop-mcp's `shellIpcDenyTargets`.
