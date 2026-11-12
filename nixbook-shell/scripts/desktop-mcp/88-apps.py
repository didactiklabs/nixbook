# Part of nixbook-desktop-mcp (see ../desktop-mcp.py). The parts run in
# order in one module namespace, as one file: a name defined in any part
# is visible in every other, and tests may replace any function.
#
# Discord, Slack, YouTube Music and Actual Budget through their bridges.

# Discord (Vesktop through its bridge): the messages through Discord's own
# client in the app (electron/discord.js), not its window. A send or a
# reaction speaks in the user's name: always asked (ask_user_yes), whatever
# the client allowed.

def discord_channel(c):
    if not isinstance(c, dict):
        return "?"
    return c.get("name", "?") + (f" ({c['guild']})" if c.get("guild") else "") + f" = {c.get('id')}"


def discord_permission(where, kind):
    """The standing-permission key of `kind` in a channel discord_channel
    named: None when its id isn't known."""
    cid = where.rsplit(" = ", 1)[1] if " = " in where else ""
    return f"discord:{kind}:{cid}" if re.fullmatch(r"\d{5,30}", cid) else None


def discord_message_line(m):
    when = str(m.get("time") or "")[5:16].replace("T", " ")
    bits = [f"id {m.get('id')}"]
    for k, label in (("replyTo", "reply to {}"), ("mentionsMe", "mentions you"), ("attachments", "{} files")):
        if m.get(k):
            bits.append(label.format(m[k]))
    if m.get("reactions"):
        bits.append(" ".join(f"{r.get('emoji')}{r.get('count')}" for r in m["reactions"][:8]))
    who = (m.get("author") or "?") + (" (you)" if m.get("mine") else "")
    return f"- {when} {who}: {m.get('content') or ''} ⟨{', '.join(bits)}⟩"


def discord_contact_hint(query):
    """On a Discord search that found nobody: the matching contacts'
    nickname and notes, where people keep someone's Discord name (Alan's
    note says "Alesio"): the agent searches that next."""
    try:
        found = accounts_call("contacts", "list", "--query", query, "--limit", "3").get("contacts") or []
    except Exception:  # noqa: BLE001 — no accounts backend: no hint
        return ""
    lines = []
    for c in found[:3]:
        bits = [f"nickname: {c['nickname']}"] if c.get("nickname") else []
        if c.get("notes"):
            bits.append("notes: " + " ".join(str(c["notes"]).split())[:300])
        if bits:
            lines.append(f"- {c.get('name') or '?'}: " + "; ".join(bits))
    if not lines:
        return ""
    return ("\nDiscord names often aren't real names. The user's contacts matching it (their Discord name may be "
            "here; search that):\n" + "\n".join(lines))


# Words that sit between "Discord" and the name in a note ("Discord: x",
# "son discord c'est x", "on Discord as x"), never a name themselves.
DISCORD_NOTE_SKIP = set(
    "is as on the his her their name username pseudo pseudonym handle tag id user account compte sur est c "
    "son sa ses de du le la les and et in dans called named known appele appelle il elle he she it s my mon ma "
    "discord server serveur vesktop dm dms pm message messages".split())


def discord_names(query):
    """[(contact name, a Discord name its contact gives)]: the nickname and
    the words just after a "Discord" in the notes of the contacts matching
    QUERY (Alan's note: "… Discord … alesio")."""
    try:
        found = accounts_call("contacts", "list", "--query", query, "--limit", "3").get("contacts") or []
    except Exception:  # noqa: BLE001 — no accounts backend: nothing
        return []
    out = []
    for c in found[:3]:
        who = c.get("name") or "?"
        if c.get("nickname"):
            out.append((who, str(c["nickname"]).strip()))
        out.extend((who, h) for h in note_discord_names(c.get("notes")))
    return list(dict.fromkeys(out))


def note_discord_names(notes):
    """The Discord names a contact's notes give: the words just after a
    "Discord". Also what the privacy mask hides (privacy_people)."""
    words = re.findall(r"[^\W_][\w.#-]*", str(notes or ""))
    out = []
    for k, w in enumerate(words):
        if "discord" not in w.lower():
            continue
        for cand in words[k + 1:k + 6]:
            if cand.lower() not in DISCORD_NOTE_SKIP and len(cand) >= 3:
                out.append(cand.split("#")[0])
    return list(dict.fromkeys(out))


DISCORD_MORE = ("unreact", "edit", "delete", "pins", "pin", "unpin", "search", "threads", "thread_create",
                "mark_read", "send_file", "members", "friends", "friend_add", "friend_remove", "presence",
                "voice_join", "voice_leave", "open", "api")


@tool(
    "discord",
    "pages",
    "Discord messages in the user's Vesktop, without its window: `status`, `find` (`query`: channels, "
    "people, DMs → ids), `channels` (`guild`; none: the servers and DMs), `read` (`channel`, `limit` ≤ "
    "50; default the open one), `send` (`channel`, `content` ≤ 2000, `reply_to` a message id), `react` "
    "(`channel`, `message`, `emoji`). A channel: an id, user:<id>, or a name. Sends and reactions are "
    "in the user's name: say what you'll send first; the user is asked again (Allow / No) before it goes. To message someone: `find` with "
    "the name as the user gave it (a placeholder as it is: the contact's Discord name is looked up), then "
    "`send`; never through Vesktop's window. Also: `edit` / `delete` (`channel`, `message`, `content`), "
    "`unreact`, `pins`, `pin` / `unpin` (`message`), `search` (`query`, `author`, `guild` or `channel`), "
    "`threads`, `thread_create` (`channel`, `name`, `message`), `mark_read`, `send_file` (`channel`, `path` "
    "of a file in the home, `content`), `members` (`guild`), `friends`, `friend_add` (`username`), "
    "`friend_remove` (`user`), `presence` (`status` online|idle|dnd|invisible, `text` a custom status), "
    "`voice_join` (`channel`) / `voice_leave`, `open` (shows a channel in Vesktop), and `api` (`method`, "
    "`path` /…, `body`, `params` its query): any other call of Discord's REST API as the user, never the "
    "account's credentials, billing or connections. Editing, deleting, files, friends, voice and a "
    "non-GET `api` call are asked to the user too.",
    obj({"action": {"type": "string", "enum": ["status", "find", "channels", "read", "send", "react"]
                    + list(DISCORD_MORE)},
         "query": {"type": "string"}, "guild": {"type": "string"}, "channel": {"type": "string"},
         "limit": {"type": "integer"}, "content": {"type": "string"}, "reply_to": {"type": "string"},
         "message": {"type": "string"}, "emoji": {"type": "string"}, "before": {"type": "string"},
         "author": {"type": "string"}, "name": {"type": "string"}, "path": {"type": "string"},
         "username": {"type": "string"}, "user": {"type": "string"}, "status": {"type": "string"},
         "text": {"type": "string"}, "method": {"type": "string"}, "body": {}, "params": {"type": "object"}},
        ["action"]),
    destructive=True,
)
def t_discord(ctx, args):
    action = as_str(args, "action", max_len=20)
    if action in DISCORD_MORE:
        return discord_more(ctx, action, args)

    def app(op, **kw):
        return electron(ctx, "discord", "app", op=op, args={k: v for k, v in kw.items() if v not in (None, "")})

    def opt(key, n=200):
        return as_str(args, key, max_len=n, required=False) or None

    if action == "status":
        r = app("status")
        if not r.get("loggedIn"):
            return [text("Vesktop runs with the bridge, but Discord isn't logged in (or still loading).")]
        return [text(f"Discord: logged in as {r.get('user')}; open: "
                     f"{discord_channel(r['current']) if r.get('current') else 'no channel'}")]
    if action == "find":
        query = as_str(args, "query", max_len=100)
        res = app("find", query=query).get("results") or []
        # Discord names often aren't real names: the one in the person's
        # contact (nickname, or after "Discord" in the notes) is searched
        # too, always, and comes first. Searched only when nothing matched,
        # a group named after them ("Anniv Alan") hid their own DM
        # ("Alesio"), and the agent went on from the group.
        known, seen = [], {str(h.get("id")) for h in res}
        for who, name in discord_names(query)[:5]:
            if name.lower() == query.lower():
                continue
            hits = [h for h in app("find", query=name).get("results") or [] if str(h.get("id")) not in seen]
            seen |= {str(h.get("id")) for h in hits}
            if hits:
                known.append(f"{who} on Discord (their contact gives {name!r}):\n"
                             + "\n".join(f"- {h.get('kind')} {discord_channel(h)}" for h in hits))
        if known and res:
            known.append(f"Also matching {query!r} by name (not necessarily them):\n"
                         + "\n".join(f"- {h.get('kind')} {discord_channel(h)}" for h in res))
        if known:
            return [text("\n\n".join(known))]
        if res:
            return [text("\n".join(f"- {h.get('kind')} {discord_channel(h)}" for h in res))]
        return [text("nothing found" + discord_contact_hint(query))]
    if action == "channels":
        guild = opt("guild", 100)
        if guild:
            r = app("channels", guild=guild)
            return [text(f"{r.get('guild')}:\n" + "\n".join(f"- {discord_channel(c)}" for c in r.get("channels") or []))]
        gs, dms = app("guilds").get("guilds") or [], app("dms").get("dms") or []
        return [text("Servers:\n" + "\n".join(f"- {g.get('name')} = {g.get('id')}" for g in gs)
                     + "\nDirect messages:\n" + "\n".join(f"- {discord_channel(c)}" for c in dms))]
    if action == "read":
        limit = max(1, min(50, int(args.get("limit") or 20))) if isinstance(args.get("limit"), int) else 20
        r = app("read", channel=opt("channel"), limit=limit)
        msgs = r.get("messages") or []
        return [text(f"{discord_channel(r.get('channel'))}, the last {len(msgs)}:\n"
                     + "\n".join(discord_message_line(m) for m in msgs))]
    if action == "send":
        channel = as_str(args, "channel", max_len=200)
        content = args.get("content")
        if not isinstance(content, str) or not content.strip():
            raise ToolError("`content`: the message to send")
        if len(content) > 2000:
            raise ToolError("a Discord message is at most 2000 characters")
        ctx.guard.check_rate()
        where = discord_channel(app("read", channel=channel, limit=1).get("channel"))
        ask_user_yes(ctx, f"Send this on Discord, to {where.rsplit(' = ', 1)[0]}?", content,
                     key=discord_permission(where, "send"),
                     label=f"Send messages on Discord, in {where.rsplit(' = ', 1)[0]}")
        r = app("send", channel=channel, content=content, reply_to=opt("reply_to", 30))
        if r.get("id"):
            return [text(f"sent to {discord_channel(r.get('channel'))} (message id {r['id']})")]
        return [text(f"handed to Discord for {discord_channel(r.get('channel'))}, no message id came back: "
                     "discord read shows whether it went")]
    if action == "react":
        ctx.guard.check_rate()
        channel = as_str(args, "channel", max_len=200)
        emoji = as_str(args, "emoji", max_len=80)
        where = discord_channel(app("read", channel=channel, limit=1).get("channel"))
        ask_user_yes(ctx, f"React {emoji} on Discord, in {where.rsplit(' = ', 1)[0]}?",
                     f"To message {as_str(args, 'message', max_len=30)}, in your name.",
                     key=discord_permission(where, "react"),
                     label=f"React on Discord, in {where.rsplit(' = ', 1)[0]}")
        r = app("react", channel=as_str(args, "channel", max_len=200), message=as_str(args, "message", max_len=30),
                emoji=as_str(args, "emoji", max_len=80))
        return [text(f"reacted {args.get('emoji')} to message {r.get('id')} in {discord_channel(r.get('channel'))}")]
    raise ToolError("action: status, find, channels, read, send or react")


DISCORD_ASK = {"edit": "edit a message", "delete": "delete a message", "send_file": "send a file",
               "friend_add": "send a friend request", "friend_remove": "remove a friend",
               "voice_join": "join a voice channel", "api": "make this call"}
FILE_SEND_MAX = 8 * 1024 * 1024


def file_payload(path):
    """(name, base64, mime) of a file in the user's home to send, at most
    FILE_SEND_MAX."""
    real = safe_home_path(path)
    if not os.path.isfile(real):
        raise ToolError(f"no file {path}")
    size = os.path.getsize(real)
    if size > FILE_SEND_MAX:
        raise ToolError(f"{path} is {size // 1024 // 1024} MB: at most {FILE_SEND_MAX // 1024 // 1024} MB")
    with open(real, "rb") as f:
        data = base64.b64encode(f.read()).decode()
    return os.path.basename(real), data, mimetypes.guess_type(real)[0] or "application/octet-stream"


def forwarded(args, keys, max_json=20000):
    """The arguments an app operation takes, checked for size."""
    out = {}
    for k in keys:
        if k in args and args[k] is not None:
            v = args[k]
            if isinstance(v, str) and len(v) > 12000:
                raise ToolError(f"`{k}` is too long")
            out[k] = v
    if len(json.dumps(out)) > max_json:
        raise ToolError("too much at once")
    return out


def app_reply(r):
    """An app operation's answer as text: compact JSON."""
    return [text(r)]


def discord_more(ctx, action, args):
    ctx.guard.check_rate()
    sent = forwarded(args, ("channel", "message", "content", "emoji", "query", "guild", "author", "limit", "name",
                            "username", "user", "status", "text", "method", "path", "body", "before"))
    if "params" in args:
        sent["query"] = args["params"]
    ask = DISCORD_ASK.get(action)
    if action == "api" and str(args.get("method") or "get").lower() == "get":
        ask = None
    if action == "send_file":
        name, data, mime = file_payload(as_str(args, "path", max_len=500))
        sent.update(name=name, data=data, mime=mime)
    if ask:
        what = "; ".join(f"{k}: {short(str(args[k]), 200)}" for k in ("channel", "message", "content", "path",
                                                                         "username", "user", "method", "body")
                         if k in args)
        ask_user_yes(ctx, f"Let the agent {ask} on Discord?", what or ask)
    return app_reply(electron(ctx, "discord", "app", op=action, args=sent))


# Slack (through its bridge): the Slack app's own Web API, with its session.
SLACK_ACTIONS = ("status", "teams", "channels", "users", "find", "read", "thread", "search", "pins", "send",
                 "schedule", "edit", "delete", "react", "unreact", "mark_read", "pin", "unpin", "upload",
                 "profile_status", "presence", "dnd", "dnd_end", "channel_create", "invite", "join", "leave",
                 "archive", "topic", "remind", "api")
SLACK_ASK = {"send": "send this", "schedule": "schedule this message", "edit": "edit a message",
             "delete": "delete a message", "react": "react", "upload": "upload a file",
             "channel_create": "create a channel", "invite": "invite people", "archive": "archive a channel",
             "leave": "leave a channel", "api": "make this call"}
SLACK_READ_METHOD = re.compile(r"\.(list|info|history|replies|get\w*|search\w*|lookup\w*)$")


@tool(
    "slack",
    "pages",
    "Slack in the user's Slack app, without its window, through Slack's own Web API with the app's session "
    "(`team`: a workspace, default the one open). Read: `status`, `teams`, `channels` (`query`), `users` "
    "(`query`), `find` (`query`: channels and people → ids), `read` (`channel`, `limit`, `before` a ts), "
    "`thread` (`channel`, `ts`), `search` (`query`, Slack's syntax: in:#x from:@y), `pins`. Act: `send` "
    "(`channel`, `content`, `thread_ts`, `broadcast`), `schedule` (… `at` unix seconds), `edit` / `delete` "
    "(`channel`, `ts`), `react` / `unreact` (`ts`, `emoji` its name), `mark_read`, `pin` / `unpin`, "
    "`upload` (`channel`, `path` of a file in the home, `content`), `profile_status` (`text`, `emoji`, "
    "`minutes`), `presence` (auto|away), `dnd` (`minutes`) / `dnd_end`, `channel_create` (`name`, "
    "`private`), `invite` (`channel`, `users`), `join` / `leave` / `archive`, `topic`, `remind` (`text`, "
    "`time`), and `api` (`method` e.g. bookmarks.list, `params`): any other Web API method, never auth, "
    "oauth, admin or apps. A channel: its id, #name, or a person (their DM). What speaks, deletes, uploads, "
    "invites or archives in the user's name is asked to them first (Allow / No); say what first. Never "
    "through Slack's window.",
    obj({"action": {"type": "string", "enum": list(SLACK_ACTIONS)}, "team": {"type": "string"},
         "query": {"type": "string"}, "channel": {"type": "string"}, "limit": {"type": "integer"},
         "before": {"type": "string"}, "ts": {"type": "string"}, "thread_ts": {"type": "string"},
         "content": {"type": "string"}, "broadcast": {"type": "boolean"}, "at": {"type": "integer"},
         "emoji": {"type": "string"}, "path": {"type": "string"}, "text": {"type": "string"},
         "minutes": {"type": "integer"}, "presence": {"type": "string", "enum": ["auto", "away"]},
         "name": {"type": "string"}, "private": {"type": "boolean"}, "users": {"type": "array", "items": {"type": "string"}},
         "topic": {"type": "string"}, "time": {"type": "string"}, "types": {"type": "string"},
         "method": {"type": "string"}, "params": {"type": "object"}}, ["action"]),
    destructive=True,
    brief=("Slack without its window: read (channels, find, read, thread, search, pins), send/edit/delete, "
           "react, upload, status, DND, channels, reminders, any Web API method (api)."),
    props={"team": None, "channel": None, "query": None, "content": None, "ts": None, "limit": None},
)
def t_slack(ctx, args):
    action = as_str(args, "action", max_len=20)
    if action not in SLACK_ACTIONS:
        raise ToolError("action: " + ", ".join(SLACK_ACTIONS))
    sent = forwarded(args, ("team", "query", "channel", "limit", "before", "ts", "thread_ts", "content", "broadcast",
                            "at", "emoji", "text", "minutes", "presence", "name", "private", "users", "topic", "time",
                            "types", "method", "params"))
    ask = SLACK_ASK.get(action)
    if action == "api" and SLACK_READ_METHOD.search(str(args.get("method") or "")):
        ask = None
    if ask:
        ctx.guard.check_rate()
    if action == "upload":
        name, data, mime = file_payload(as_str(args, "path", max_len=500))
        sent.update(name=name, data=data)
    if ask:
        what = "; ".join(f"{k}: {short(str(args[k]), 300)}" for k in ("channel", "content", "ts", "path", "users",
                                                                         "name", "method", "params") if k in args)
        ask_user_yes(ctx, f"Let the agent {ask} on Slack?", what or ask)
    return app_reply(electron(ctx, "slack", "app", op=action, args=sent))


# YouTube Music's library (through its bridge): playlists, likes,
# subscriptions, history; playback and the queue are the youtube-music
# MCP server's.
YTM_ACTIONS = ("status", "playlists", "playlist", "liked", "history", "library", "playlist_create", "playlist_add",
               "playlist_remove", "playlist_rename", "playlist_delete", "like", "dislike", "unlike", "subscribe",
               "unsubscribe", "innertube")


@tool(
    "youtube_music",
    "pages",
    "The user's YouTube Music library in pear-desktop, without its window (playing and the queue: the "
    "youtube-music server's tools). `playlists`, `playlist` (`playlist`: its id or title; its tracks with "
    "videoId), `liked`, `history`, `library` (`kind` songs|albums|artists|subscriptions), `playlist_create` "
    "(`title`, `description`, `privacy` private|unlisted|public, `videos`), `playlist_add` / "
    "`playlist_remove` (`playlist`, `videos` videoIds), `playlist_rename` (`playlist`, `title`, "
    "`description`, `privacy`), `playlist_delete` (asked to the user first), `like` / `dislike` / `unlike` "
    "(`video`), `subscribe` / `unsubscribe` (`channel` UC…), `innertube` (`endpoint` e.g. browse, `body`): "
    "any other call of the page's own API, never the account's settings. videoIds come from the "
    "youtube-music server's search or a playlist.",
    obj({"action": {"type": "string", "enum": list(YTM_ACTIONS)}, "playlist": {"type": "string"},
         "limit": {"type": "integer"}, "kind": {"type": "string", "enum": ["songs", "albums", "artists", "subscriptions"]},
         "title": {"type": "string"}, "description": {"type": "string"},
         "privacy": {"type": "string", "enum": ["private", "unlisted", "public"]},
         "videos": {"type": "array", "items": {"type": "string"}}, "video": {"type": "string"},
         "channel": {"type": "string"}, "endpoint": {"type": "string"}, "body": {"type": "object"}}, ["action"]),
    destructive=True,
    brief="YouTube Music's library without its window: playlists (list, read, create, add, remove, rename, delete), likes, subscriptions, history.",
    props={"playlist": None, "videos": None, "video": None, "title": None},
)
def t_youtube_music(ctx, args):
    action = as_str(args, "action", max_len=20)
    if action not in YTM_ACTIONS:
        raise ToolError("action: " + ", ".join(YTM_ACTIONS))
    sent = forwarded(args, ("playlist", "limit", "kind", "title", "description", "privacy", "videos", "video",
                            "channel", "endpoint", "body"))
    if action not in ("status", "playlists", "playlist", "liked", "history", "library"):
        ctx.guard.check_rate()
    if action == "playlist_delete" or (action == "innertube" and "delete" in str(args.get("endpoint") or "")):
        ask_user_yes(ctx, "Let the agent delete a YouTube Music playlist?" if action == "playlist_delete"
                     else f"Let the agent call {short(str(args.get('endpoint')), 60)} on YouTube Music?",
                     str(args.get("playlist") or args.get("body") or ""))
    return app_reply(electron(ctx, "youtube-music", "app", op=action, args=sent))


# Actual Budget (through its bridge): the money questions ("how much did I
# spend on food this month?", "what's left in groceries?") answered from
# Actual's own client in its page (electron/actual.js: $send / $query, its
# public API's handlers), never its window. `budget` only reads;
# `budget_edit` adds, changes or deletes a transaction, sets or moves a
# category's budget and creates a category, through the same public API
# (no sync, import, bank link, account or budget file), so no agent clicks
# or types in Actual. A delete is the user's own yes (ask_user_yes); the
# rest follows the trust ladder in the shell's sessions (told after by
# default). Payees and notes go through the privacy mask like every reply
# (call_tool).

BUDGET_ACTIONS = ("status", "summary", "category", "transactions", "accounts", "schedules", "rules", "payees")
BUDGET_NOT_OPEN = ("Actual Budget isn't open with nixbook's bridge: the user opens it from the launcher (\"Actual "
                   "Budget\") and their budget file, then asks again (if it was already open, quit it completely "
                   "and start it again from the launcher). Nothing else reads it: don't screenshot it")


def money_text(amount, currency=""):
    try:
        n = float(amount)
    except (TypeError, ValueError):
        return str(amount)
    sign = "-" if n < 0 else ""
    return f"{sign}{abs(n):,.2f}" + (f" {currency}" if currency else "")


def budget_month_line(m, cur):
    # Actual: spending is negative; said as spent, positive.
    return (f"{m.get('month')}: income {money_text(m.get('income'), cur)}, budgeted "
            f"{money_text(abs(m.get('budgeted') or 0), cur)}, spent {money_text(-(m.get('spent') or 0), cur)}, "
            f"to budget {money_text(m.get('toBudget'), cur)}")


def budget_category_line(c, cur):
    if c.get("income"):
        return f"- {c.get('name')} (income): received {money_text(c.get('spent'), cur)}"
    where = f" ({c['group']})" if c.get("group") else ""
    kind = "group " if c.get("kind") == "group" else ""
    return (f"- {kind}{c.get('name')}{where}: budgeted {money_text(c.get('budgeted'), cur)}, spent "
            f"{money_text(-(c.get('spent') or 0), cur)}, left {money_text(c.get('balance'), cur)}"
            # Names (category) or the categories themselves (summary).
            + (f" — its categories: {', '.join(str(x.get('name') if isinstance(x, dict) else x) for x in c['categories'][:20])}"
               if c.get("categories") else ""))


@tool(
    "budget",
    "pages",
    "The user's money in Actual Budget, read only, without its window (budget_edit changes it): "
    "`summary` (a month's income, budgeted, spent, to budget and each group; default this month, "
    "`month` YYYY-MM), `category` (`query`: a category or group as the user said it — food, "
    "groceries —: budgeted, spent and what's left that month), `transactions` (`query` words in the "
    "payee, notes or category, `category`, `account`, `from`/`to` YYYY-MM-DD — default this month "
    "so far —, `limit`; their count, totals and each one's id, for budget_edit), `accounts` (balances), "
    "`schedules` (each one's id, next date, amount, payee, account, how it repeats), `rules` (as Actual keeps "
    "them: ids), `payees` (`query` to narrow), `status`. Spent amounts are said positive. Answer with the figure asked for, not the whole list.",
    obj({"action": {"type": "string", "enum": list(BUDGET_ACTIONS)},
         "query": {"type": "string"}, "category": {"type": "string"}, "account": {"type": "string"},
         "month": {"type": "string", "description": "YYYY-MM (default this month)"},
         "from": {"type": "string", "description": "YYYY-MM-DD"}, "to": {"type": "string", "description": "YYYY-MM-DD"},
         "limit": {"type": "integer", "description": "Transactions listed (default 20, at most 100)"}}, ["action"]),
    read_only=True,
    brief=("Money in Actual Budget, read only: summary (a month), category (query: food…: spent, left), "
           "transactions (query, category, account, from/to: totals, ids), accounts, schedules, rules, payees."),
    props={"query": None, "category": None, "account": None, "month": "YYYY-MM", "from": None, "to": None,
           "limit": None},
)
def t_budget(ctx, args):
    action = as_str(args, "action", max_len=20)
    if action not in BUDGET_ACTIONS:
        raise ToolError("action: " + ", ".join(BUDGET_ACTIONS))
    if "actual" not in bridged_apps() and "actual" not in unbridged_apps():
        raise ToolError(BUDGET_NOT_OPEN)

    def app(op, **kw):
        try:
            return electron(ctx, "actual", "app", op=op, args={k: v for k, v in kw.items() if v not in (None, "")})
        except ToolError as e:
            if "isn't reachable" in str(e):
                raise ToolError(BUDGET_NOT_OPEN)
            raise

    def opt(key, n=100, pattern=None):
        return as_str(args, key, max_len=n, required=False, pattern=pattern) or None

    if action == "status":
        r = app("status")
        if not r.get("open"):
            return [text("Actual Budget runs with the bridge, but no budget is open in it.")]
        months = r.get("months") or {}
        return [text(f"Actual Budget: the budget {r.get('budget')!r} is open"
                     + (f" ({months.get('first')} to {months.get('last')})" if months else "")
                     + (f", in {r['currency']}" if r.get("currency") else "") + ".")]
    if action == "summary":
        r = app("month", month=opt("month", 7, r"\d{4}-\d{2}"))
        cur = r.get("currency") or ""
        lines = [budget_month_line(r, cur)]
        lines += [budget_category_line(g, cur) for g in r.get("groups") or [] if not g.get("hidden")]
        return [text("\n".join(lines))]
    if action == "category":
        query = as_str(args, "query", max_len=100)
        r = app("categories", query=query, month=opt("month", 7, r"\d{4}-\d{2}"))
        cur = r.get("currency") or ""
        if not r.get("matches"):
            return [text(f"No category or group in Actual matches {query!r}. Its categories: "
                         + ", ".join(r.get("names") or []))]
        return [text(f"{r.get('month')}:\n" + "\n".join(budget_category_line(c, cur) for c in r["matches"]))]
    if action == "transactions":
        limit = max(1, min(100, int(args["limit"]))) if isinstance(args.get("limit"), int) else 20
        r = app("transactions", query=opt("query"), category=opt("category"), account=opt("account"),
                limit=limit, **{"from": opt("from", 10, r"\d{4}-\d{2}-\d{2}"), "to": opt("to", 10, r"\d{4}-\d{2}-\d{2}")})
        cur = r.get("currency") or ""
        which = " ".join(bit for bit in (
            f"matching {args['query']!r}" if args.get("query") else "",
            f"in {', '.join(r['categories'])}" if r.get("categories") else "",
            f"from {', '.join(r['accounts'])}" if r.get("accounts") else "") if bit)
        head = (f"{r.get('count')} transactions {which + ' ' if which else ''}from {r.get('from')} to {r.get('to')}: "
                f"spent {money_text(-(r.get('spent') or 0), cur)}, received {money_text(r.get('received'), cur)}, "
                f"net {money_text(r.get('total'), cur)}")
        rows = [f"- {t.get('date')} {money_text(t.get('amount'), cur)} {t.get('payee') or '?'}"
                + (f" [id {t['id']}]" if t.get("id") else "")
                + (f" · {t['category']}" if t.get("category") else "") + (f" · {t['account']}" if t.get("account") else "")
                + (f" · {t['notes']}" if t.get("notes") else "") for t in r.get("transactions") or []]
        more = (r.get("count") or 0) - len(rows)
        return [text("\n".join([head] + rows + ([f"… and {more} more (`limit`)"] if more > 0 else [])))]
    if action == "schedules":
        r = app("schedules")
        cur = r.get("currency") or ""
        rows = []
        for x in r.get("schedules") or []:
            a = x.get("amount")
            amt = (f"{money_text(a.get('from'), cur)} to {money_text(a.get('to'), cur)}" if isinstance(a, dict)
                   else ("about " if x.get("amount_op") == "isapprox" else "") + money_text(a, cur))
            d = x.get("date")
            how = (f"every {d.get('interval', 1)} {d.get('frequency')}" + (f" until {d['endDate']}" if d.get("endDate") else "")
                   if isinstance(d, dict) else f"once, {d}")
            rows.append(f"- [id {x.get('id')}] {x.get('name') or x.get('payee') or '?'}: {amt}, {how}, next "
                        f"{x.get('next_date') or '—'}" + (f", {x['account']}" if x.get("account") else "")
                        + (", posted by itself" if x.get("auto_post") else "") + (" (completed)" if x.get("completed") else ""))
        return [text("Schedules:\n" + ("\n".join(rows) or "none"))]
    if action == "rules":
        return [text(app("rules"))]
    if action == "payees":
        return [text(app("payees", query=opt("query")))]
    r = app("accounts")
    cur = r.get("currency") or ""
    lines = [f"- {a.get('name')}: {money_text(a.get('balance'), cur)}"
             + (" (off budget)" if a.get("offBudget") else "") for a in r.get("accounts") or [] if not a.get("closed")]
    return [text("Accounts:\n" + ("\n".join(lines) or "none"))]


BUDGET_EDIT_ACTIONS = (
    "add", "update", "delete", "set_budget", "move_budget", "set_carryover", "hold", "reset_hold",
    "create_category", "category_update", "category_delete", "group_create", "group_update", "group_delete",
    "account_create", "account_update", "account_close", "account_reopen", "account_delete",
    "payee_create", "payee_update", "payee_delete", "payee_merge",
    "schedule_create", "schedule_update", "schedule_delete", "schedule_skip", "schedule_post",
    "rule_create", "rule_update", "rule_delete", "sync", "bank_sync", "call")
# What deletes, closes or merges: the user's own yes first (a notification).
BUDGET_EDIT_ASK = {"delete": "delete a transaction", "category_delete": "delete a category",
                   "group_delete": "delete a category group", "account_close": "close an account",
                   "account_delete": "delete an account", "payee_delete": "delete a payee",
                   "payee_merge": "merge payees", "schedule_delete": "delete a schedule",
                   "rule_delete": "delete a rule"}
BUDGET_EDIT_KEYS = ("id", "amount", "amount_to", "amount_op", "payee", "category", "account", "date", "notes",
                    "cleared", "month", "from", "to", "name", "group", "hidden", "income", "offbudget", "balance",
                    "transfer", "transfer_account", "transfer_category", "transfer_to", "splits", "merge", "flag",
                    "frequency", "interval", "start", "end_date", "occurrences", "skip_weekend", "weekend",
                    "approx_date", "auto_post", "completed", "stage", "conditions_op", "conditions", "actions",
                    "handler", "args")


@tool(
    "budget_edit",
    "pages",
    "Change anything in the user's Actual Budget through its own client, without its window (never click or "
    "type in Actual). Amounts in the budget's currency, a transaction's spending NEGATIVE, income positive; "
    "accounts, categories, groups and payees by name (matched loosely: grocery finds Groceries; an unsure one "
    "is refused with the names: ask the user, don't guess); ids from the `budget` tool. "
    "Transactions: `add` (`amount`, `payee`, `category`, `account` — left out when there is one on-budget "
    "account —, `date` YYYY-MM-DD default today, `notes`, `cleared`, `transfer_to` an account for a transfer, "
    "`splits` [{amount, category, notes}] adding up to it), `update` (`id` and only the fields to change; "
    "`category`/`payee` empty clears it), `delete` (`id`). "
    "Budget (`month` YYYY-MM, default this month): `set_budget` (`category`, `amount`), `move_budget` "
    "(`from`, `to`, `amount` positive), `set_carryover` (`category`, `flag`), `hold` (`amount` for next "
    "month), `reset_hold`. "
    "Categories: `create_category` (`name`, `group`), `category_update` (`category`, `name`, `hidden`, "
    "`group`), `category_delete` (`category`, `transfer` its budget to a category), `group_create` (`name`, "
    "`income`), `group_update` (`group`, `name`, `hidden`), `group_delete` (`group`, `transfer`). "
    "Accounts: `account_create` (`name`, `offbudget`, `balance` its starting balance), `account_update` "
    "(`account`, `name`, `offbudget`), `account_close` (`account`, `transfer_account`/`transfer_category` for "
    "what's left), `account_reopen`, `account_delete`. "
    "Payees: `payee_create` (`name`), `payee_update` (`payee`, `name` the new one), `payee_delete`, "
    "`payee_merge` (`payee` to keep, `merge` [names folded into it]). "
    "Schedules (`budget` schedules gives ids): `schedule_create` (`amount`, `amount_op` is|isapprox|isbetween "
    "with `amount_to`, `payee`, `account`, `name`; `date` for one payment, or `frequency` "
    "daily|weekly|monthly|yearly with `interval`, `start`, `end_date` or `occurrences`, `skip_weekend`, "
    "`weekend` before|after, `approx_date`; `auto_post` to add the transaction by itself), `schedule_update` "
    "(`id`, the same fields, `completed`), `schedule_delete`, `schedule_skip` (its next date), `schedule_post` "
    "(the transaction now). "
    "Rules (`budget` rules shows them): `rule_create` (`conditions` [{field, op, value}], `actions` [{field, "
    "op: set, value}], `conditions_op` and|or, `stage` pre|post; payee/category/account values by name, "
    "amounts in units), `rule_update` (`id`, the whole rule), `rule_delete` (`id`). "
    "`sync` (the sync server), `bank_sync` (`account`, or every linked one). "
    "`call`: any other handler of Actual's public API (`handler` \"api/…\", `args` as @actual-app/api sends "
    "them: ids and cents), never one acting on the budget file. "
    "Deleting, closing or merging asks the user first. Say what was done, with the amounts.",
    obj({"action": {"type": "string", "enum": list(BUDGET_EDIT_ACTIONS)},
         "id": {"type": "string", "description": "A transaction's, schedule's or rule's id (the budget tool)"},
         "amount": {"type": "number", "description": "In the budget's currency; a transaction's spending negative"},
         "amount_to": {"type": "number"}, "amount_op": {"type": "string", "enum": ["is", "isapprox", "isbetween"]},
         "payee": {"type": "string"}, "category": {"type": "string"}, "account": {"type": "string"},
         "date": {"type": "string", "description": "YYYY-MM-DD"}, "notes": {"type": "string"},
         "cleared": {"type": "boolean"}, "month": {"type": "string", "description": "YYYY-MM (default this month)"},
         "from": {"type": "string"}, "to": {"type": "string"}, "name": {"type": "string"},
         "group": {"type": "string"}, "hidden": {"type": "boolean"}, "income": {"type": "boolean"},
         "offbudget": {"type": "boolean"}, "balance": {"type": "number"}, "transfer": {"type": "string"},
         "transfer_account": {"type": "string"}, "transfer_category": {"type": "string"},
         "transfer_to": {"type": "string"}, "flag": {"type": "boolean"},
         "splits": {"type": "array", "items": {"type": "object"}},
         "merge": {"type": "array", "items": {"type": "string"}},
         "frequency": {"type": "string", "enum": ["daily", "weekly", "monthly", "yearly"]},
         "interval": {"type": "integer"}, "start": {"type": "string"}, "end_date": {"type": "string"},
         "occurrences": {"type": "integer"}, "skip_weekend": {"type": "boolean"},
         "weekend": {"type": "string", "enum": ["before", "after"]}, "approx_date": {"type": "boolean"},
         "auto_post": {"type": "boolean"}, "completed": {"type": "boolean"},
         "stage": {"type": "string", "enum": ["pre", "post"]}, "conditions_op": {"type": "string", "enum": ["and", "or"]},
         "conditions": {"type": "array", "items": {"type": "object"}},
         "actions": {"type": "array", "items": {"type": "object"}},
         "handler": {"type": "string", "description": "call: an api/… handler"},
         "args": {"description": "call: its arguments"}}, ["action"]),
    destructive=True,
    brief=("Change anything in Actual Budget without its window: transactions (add with transfers and splits, "
           "update, delete), budgets, categories and groups, accounts, payees, schedules, rules, sync, any api/ "
           "handler (call)."),
    props={"id": None, "amount": None, "payee": None, "category": None, "account": None, "date": "YYYY-MM-DD",
           "month": "YYYY-MM", "name": None, "frequency": None},
)
def t_budget_edit(ctx, args):
    action = as_str(args, "action", max_len=20)
    if action not in BUDGET_EDIT_ACTIONS:
        raise ToolError("action: " + ", ".join(BUDGET_EDIT_ACTIONS))
    if "actual" not in bridged_apps() and "actual" not in unbridged_apps():
        raise ToolError(BUDGET_NOT_OPEN)

    def opt(key, n=100, pattern=None):
        return as_str(args, key, max_len=n, required=False, pattern=pattern) or None

    def amount(required=True):
        v = args.get("amount")
        if v is None and not required:
            return None
        if isinstance(v, bool) or not isinstance(v, (int, float)) or abs(v) > 1e9:
            raise ToolError("`amount`: a number in the budget's currency (a transaction's spending negative)")
        return v

    def app(op, **kw):
        try:
            return electron(ctx, "actual", "app", op=op, args={k: v for k, v in kw.items() if v is not None})
        except ToolError as e:
            if "isn't reachable" in str(e):
                raise ToolError(BUDGET_NOT_OPEN)
            raise

    ctx.guard.check_rate()
    ask = BUDGET_EDIT_ASK.get(action)
    if action == "call" and re.search(r"delete|close|merge", str(args.get("handler") or "")):
        ask = f"run {str(args.get('handler'))[:60]}"
    if ask and action != "delete":
        what = ", ".join(f"{k}: {short(str(args[k]), 60)}" for k in ("account", "category", "group", "payee", "merge",
                                                                    "id", "handler") if k in args)
        ask_user_yes(ctx, f"Let the agent {ask} in Actual Budget?", what or ask)
    if action not in ("add", "update", "delete", "set_budget", "move_budget", "create_category"):
        sent = {}
        for k in BUDGET_EDIT_KEYS:
            if k not in args:
                continue
            v = args[k]
            if isinstance(v, str) and len(v) > 500:
                raise ToolError(f"`{k}` is longer than 500 characters")
            sent[k] = v
        if len(json.dumps(sent)) > 20000:
            raise ToolError("too much at once")
        r = app(action, **sent)
        return [text(r)]
    date = opt("date", 10, r"\d{4}-\d{2}-\d{2}")
    month = opt("month", 7, r"\d{4}-\d{2}")
    cleared = args.get("cleared") if isinstance(args.get("cleared"), bool) else None
    if action == "add":
        splits = args.get("splits") if isinstance(args.get("splits"), list) else None
        if splits is not None and (len(splits) > 50 or not all(isinstance(x, dict) for x in splits)):
            raise ToolError("`splits`: up to 50 {amount, category, notes}")
        r = app("add", amount=amount(required=splits is None), payee=opt("payee"), category=opt("category"),
                account=opt("account"), date=date, notes=opt("notes", 500), cleared=cleared,
                transfer_to=opt("transfer_to"), splits=splits)
        t, cur = r.get("added") or {}, r.get("currency") or ""
        return [text(f"Added {money_text(t.get('amount'), cur)} on {t.get('date')}"
                     + (f" at {t['payee']}" if t.get("payee") else "") + (f" in {t['category']}" if t.get("category") else "")
                     + (f", {t['account']}" if t.get("account") else "") + (f" [id {t['id']}]" if t.get("id") else "") + ".")]
    if action == "update":
        tid = as_str(args, "id", max_len=64)
        # An empty payee or category clears it.
        fields = {k: "" if args[k] == "" else as_str(args, k, max_len=500 if k == "notes" else 100)
                  for k in ("payee", "category", "notes") if k in args}
        r = app("update", id=tid, amount=amount(required=False), date=date, cleared=cleared, **fields)
        return [text(f"Updated the transaction {r.get('updated')}: {', '.join(r.get('changed') or [])}.")]
    if action == "delete":
        tid = as_str(args, "id", max_len=64)
        ask_user_yes(ctx, "Let the agent delete a transaction in Actual Budget?",
                     f"Transaction {tid}" + (f" ({args['notes']})" if isinstance(args.get("notes"), str) else ""))
        r = app("delete", id=tid)
        d, cur = r.get("deleted") or {}, r.get("currency") or ""
        return [text(f"Deleted the transaction of {money_text(d.get('amount'), cur)} on {d.get('date')}.")]
    if action == "set_budget":
        r = app("set_budget", category=as_str(args, "category", max_len=100), amount=amount(), month=month)
        cur = r.get("currency") or ""
        return [text(f"{r.get('category')}, {r.get('month')}: budgeted {money_text(r.get('budgeted'), cur)} "
                     f"(was {money_text(r.get('before'), cur)}).")]
    if action == "move_budget":
        r = app("move_budget", **{"from": as_str(args, "from", max_len=100), "to": as_str(args, "to", max_len=100)},
                amount=amount(), month=month)
        cur, f, t = r.get("currency") or "", r.get("from") or {}, r.get("to") or {}
        return [text(f"Moved {money_text(r.get('moved'), cur)} in {r.get('month')} from {f.get('category')} "
                     f"(now {money_text(f.get('budgeted'), cur)}) to {t.get('category')} (now "
                     f"{money_text(t.get('budgeted'), cur)}).")]
    r = app("create_category", name=as_str(args, "name", max_len=100), group=as_str(args, "group", max_len=100))
    if r.get("exists"):
        e = r["exists"]
        return [text(f"{e.get('name')} is already a category of {e.get('group')}.")]
    c = r.get("created") or {}
    return [text(f"Created the category {c.get('name')} in {c.get('group')}.")]
