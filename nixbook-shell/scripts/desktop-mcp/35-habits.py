# Part of nixbook-desktop-mcp (see ../desktop-mcp.py). The parts run in
# order in one module namespace, as one file: a name defined in any part
# is visible in every other, and tests may replace any function.
#
# The habits and music digests, and the personal context.

# The habits digests, kept while their files and the hour stay the same
# (re-folding the whole history for every context was most of its cost).
_DIGEST_MEMO = {}


def _digest_memo(kind, cfg, now, compute):
    def stamp(path):
        try:
            st = os.stat(path)
            return st.st_mtime_ns, st.st_size
        except OSError:
            return None
    lt = time.localtime(now or time.time())
    key = (kind, stamp(habits_path()), stamp(habits_log_path()), lt.tm_yday, lt.tm_hour,
           json.dumps({k: cfg.get(k) for k in sorted(cfg) if str(k).startswith(("habits", "music"))}, default=str))
    if key not in _DIGEST_MEMO:
        if len(_DIGEST_MEMO) > 32:
            _DIGEST_MEMO.clear()
        _DIGEST_MEMO[key] = compute()
    return _DIGEST_MEMO[key]


def habits_digest(cfg, now=None):
    """The line of the memory digest about the user's habits."""
    if not habits_on(cfg) or cfg.get("habitsAgents", "digest") == "off":
        return ""
    if now is None:
        return _digest_memo("habits", cfg, None, lambda: _habits_digest(cfg, None))
    return _habits_digest(cfg, now)


def _habits_digest(cfg, now=None):
    lines = habits_now(read_habits(), now or time.time())
    if not lines:
        return ""
    return "The user's habits (counted on this machine from their own use). " + ". ".join(lines) + "."


@tool(
    "habits",
    "memory",
    "What the user usually does on this computer, learned from their own "
    "use (apps and times only): `now` (default) the apps and layout they "
    "use at this time and how their sessions usually start, to set up "
    "\"my usual session\" or tell what a vague request means; `week` the "
    "time per app this week; `day` what they used on a date, hour by hour "
    "(only if the user shares it); `music` their music taste from what they "
    "play on any player (favourite artists and tracks, lately, around this "
    "hour, often skipped), to pick music they'll like or talk about it.",
    obj({
        "what": {"type": "string", "enum": ["now", "week", "day", "music"]},
        "date": {"type": "string", "description": "For day: YYYY-MM-DD (default: yesterday)"},
    }),
    read_only=True,
)
def t_habits(ctx, args):
    cfg = ctx.cfg
    share = cfg.get("habitsAgents", "digest")
    if not habits_on(cfg) or share == "off":
        raise ToolError("the user doesn't share their usage habits with agents")
    what = args.get("what") or "now"
    data, now = read_habits(), time.time()
    if what == "music":
        if not music_on(cfg):
            raise ToolError("the user doesn't let their music be recorded")
        lines = music_taste(data, now, full=True)
        return [text("\n".join(lines) if lines else "No music recorded yet.")]
    if what == "week":
        return [text(week_report(data, now))]
    if what == "day":
        if share != "timeline":
            raise ToolError("the user doesn't share their day by day timeline with agents (only their habits: `now`)")
        date = as_str(args, "date", required=False, max_len=10) or time.strftime(
            "%Y-%m-%d", time.localtime(now - 86400))
        return [text(day_timeline(data, date))]
    lines = habits_now(data, now)
    return [text("\n".join(lines) if lines else "Not enough usage recorded yet to tell habits.")]


def learn_alias(cfg, word, app):
    """A word typed in the launcher before opening an app that its name
    doesn't contain ("photo" -> darktable): after HABIT_ALIAS_SEEN times,
    an alias of the desktop memory (launch_app resolves it)."""
    word = fold(word).strip()
    if not habits_on(cfg) or habits_paused() or not re.fullmatch(r"[a-z][a-z0-9 ]{2,23}", word):
        return None
    entry = applications().get(app)
    if not entry or _any_match(cfg.get("habitsIgnoreApps"), app):
        return None
    if word in app.lower() or word in fold(entry.get("Name") or ""):
        return None  # found by its name already
    with Habits() as h:
        seen = h.data["aliasSeen"].setdefault(word, {})
        seen[app] = seen.get(app, 0) + 1
        if len(h.data["aliasSeen"]) > 200:
            del h.data["aliasSeen"][next(iter(h.data["aliasSeen"]))]
        h.save()
        n = seen[app]
    if n < HABIT_ALIAS_SEEN:
        return None
    with Memory() as m:
        if m.data["aliases"].get(word) == app:
            return None
        m.data["aliases"][word] = app
        m.save()
    return word


def habits_append(records):
    """Records appended to habits.log, under the lock but without reading
    habits.json: what the recorder and the layouts write."""
    if not records:
        return
    os.makedirs(habits_dir(), mode=0o700, exist_ok=True)
    lockfd = os.open(habits_path() + ".lock", os.O_WRONLY | os.O_CREAT, 0o600)
    try:
        fcntl.flock(lockfd, fcntl.LOCK_EX)
        fd = os.open(habits_log_path(), os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
        with os.fdopen(fd, "a", encoding="utf-8") as f:
            f.write("".join(json.dumps(r, separators=(",", ":"), ensure_ascii=False) + "\n" for r in records))
    finally:
        fcntl.flock(lockfd, fcntl.LOCK_UN)
        os.close(lockfd)



# -- music taste ---------------------------------------------------------------
# What the user listens to, on any player (MPRIS: Spotify, YouTube Music,
# mpv…), counted by the habits recorder from `playerctl --follow`: a track
# heard MUSIC_MIN_PLAY seconds (or half of a short one) is a play, less is
# a skip. Artist, title and album only; no ads or podcast episodes, nothing
# from web browsers (videos, not music: habitsMusicIgnorePlayers), nothing
# while the habits are paused. Agents get the favourite artists and what
# the user has been listening to lately; `habits music` the whole picture.

MUSIC_MIN_PLAY = 30  # s: listened this long (or half a short track): a play
MUSIC_MIN_HEARD = 3  # s: less is passing through, not even a skip
# The player's whole bus name ({{playerInstance}}, "chromium.instance1234"):
# {{playerName}} is only its first word ("chromium"), not enough to ask an
# Electron app's Identity (MusicTracker.name).
MUSIC_FORMAT = "\t".join(["{{playerInstance}}", "{{status}}", "{{xesam:artist}}", "{{xesam:title}}",
                          "{{xesam:album}}", "{{mpris:length}}", "{{mpris:trackid}}"])
MUSIC_NOT_MUSIC = re.compile(r"(^|[:/])(ad|ads|episode|episodes)([:/]|$)", re.IGNORECASE)
MUSIC_TITLE_NOISE = re.compile(
    r"\s*[(\[](?:official|lyrics?|audio|video|music video|visuali[sz]er|hd|hq|4k|explicit|"
    r"(?:\d{4} )?remaster(?:ed)?(?: \d{4})?|live)[^)\]]*[)\]]", re.IGNORECASE)


def music_on(cfg):
    return habits_on(cfg) and bool(cfg.get("habitsMusic"))


def music_artists(artist):
    """The artists of a track: Spotify joins several with commas, YouTube
    names channels "X - Topic" or "XVEVO"; a featured artist counts too."""
    a = re.sub(r"\s*-\s*Topic$|VEVO$", "", artist or "").strip()
    parts = re.split(r"\s*,\s*|\s+(?:feat\.?|ft\.?|featuring)\s+", a, flags=re.IGNORECASE)
    out = []
    for p in parts:
        p = p.strip()
        if p and p.lower() not in (x.lower() for x in out):
            out.append(p)
    return out


def music_title(title):
    return MUSIC_TITLE_NOISE.sub("", title or "").strip()


def player_label(player):
    name = player.split(".")[0]
    return {"spotify": "Spotify", "youtubemusic": "YouTube Music", "youtube_music": "YouTube Music", "youtube-music": "YouTube Music", "pear": "YouTube Music",
            "mpv": "mpv", "vlc": "VLC", "kdeconnect": "phone (KDE Connect)"}.get(name.lower(), name)


MUSIC_BROWSER_IDENTITY = re.compile(r"chrom|firefox|mozilla|brave|vivaldi|opera|edge|zen|librewolf|floorp|browser",
                                    re.IGNORECASE)


def mpris_identity(player):
    """A player's MPRIS Identity ("Chromium", "com.github.th_ch.youtube_music"), None if unknown."""
    try:
        out = subprocess.run(["busctl", "--user", "get-property", f"org.mpris.MediaPlayer2.{player}",
                              "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2", "Identity"],
                             capture_output=True, text=True, timeout=3).stdout
    except (OSError, subprocess.TimeoutExpired):
        return None
    if not out.startswith("s "):
        return None
    try:
        return str(json.loads(out[2:].strip()))
    except ValueError:
        return None


class MusicTracker:
    """The track each player is on and how long it played: a play record
    when the player moves to another track, stops for good or goes away."""

    def __init__(self, cfg):
        self.cfg = cfg
        self.players = {}  # player -> {"key", "start", "heard", "since", "length"}
        self.names = {}  # MPRIS name -> the player's name (None: ignored)

    def name(self, player):
        """What a player's tracks count under, None when ignored: playerctld
        mirrors the others, browsers publish their tabs' videos. Electron
        apps take a browser's bus name too (YouTube Music is
        chromium.instanceN): those count, told apart by their MPRIS Identity
        (com.github.th_ch.youtube_music, not Chromium)."""
        if player in self.names:
            return self.names[player]
        name = player.split(".")[0]
        if player.startswith("playerctld"):
            name = None
        elif _any_match(self.cfg.get("habitsMusicIgnorePlayers"), player):
            ident = mpris_identity(player)
            if ident is None:
                return None  # not cached: asked again on its next track
            # "youtube_music" either way: its AppImage said com.github.th_ch.youtube_music,
            # the native build com.github.th-ch.youtube-music (one history).
            name = None if MUSIC_BROWSER_IDENTITY.search(ident) else (
                ident.rsplit(".", 1)[-1].replace("-", "_") if " " not in ident else ident)
        self.names[player] = name
        return name

    def line(self, line, now):
        """A line of `playerctl --follow` (MUSIC_FORMAT); the play records
        it ends."""
        f = line.rstrip("\n").split("\t")
        player = self.name(f[0]) if len(f) >= 7 and f[0] else None
        if not player:
            return []
        _, status, artist, title, album, length, trackid = f[:7]
        key = [artist.strip(), title.strip(), album.strip()]
        out = []
        cur = self.players.get(player)
        if cur and cur["key"] != key:
            out += self.end(player, now)
            cur = None
        if not key[0] or not key[1] or MUSIC_NOT_MUSIC.search(trackid):
            return out
        if not cur:
            try:
                secs = int(length) / 1e6 if length else 0
            except ValueError:
                secs = 0
            cur = self.players[player] = {"key": key, "start": now, "heard": 0.0, "since": None, "length": secs}
        if status == "Playing":
            if cur["since"] is None:
                cur["since"] = now
        elif cur["since"] is not None:
            cur["heard"] += now - cur["since"]
            cur["since"] = None
            if status == "Stopped":
                out += self.end(player, now)
        return out

    def end(self, player, now):
        cur = self.players.pop(player, None)
        if not cur:
            return []
        heard = cur["heard"] + (now - cur["since"] if cur["since"] is not None else 0)
        if heard < MUSIC_MIN_HEARD or habits_paused():
            return []
        artist, title, album = cur["key"]
        return [{"m": [int(cur["start"]), int(heard), player, artist, title, album, int(cur["length"])]}]

    def gone(self, players, now):
        """The players still there (`playerctl -l`): the others' tracks end."""
        out = []
        for player in [p for p in self.players if p not in players]:
            out += self.end(player, now)
        return out

    def stale(self, now):
        """A track playing far longer than it lasts: its player stopped
        without a word (crashed, or a missed event)."""
        out = []
        for player, cur in list(self.players.items()):
            heard = cur["heard"] + (now - cur["since"] if cur["since"] is not None else 0)
            limit = (cur["length"] * 3 if cur["length"] else 1800) + 300
            if heard > limit or (cur["since"] is None and now - cur["start"] > 6 * 3600):
                out += self.end(player, now)
        return out

    def close(self, now):
        out = []
        for player in list(self.players):
            out += self.end(player, now)
        return out


def music_plays(data, since=0):
    """The plays since `since`: (start, heard, player, [artists], title,
    album, times played, skipped)."""
    out = []
    for rec in data.get("plays") or []:
        try:
            start, heard, player, artist, title, album, length = rec[:7]
        except (TypeError, ValueError):
            continue
        if start < since:
            continue
        need = min(MUSIC_MIN_PLAY, length / 2) if length else MUSIC_MIN_PLAY
        skipped = heard < need
        times = 0 if skipped else max(1, round(heard / length)) if length else 1
        out.append((start, heard, player, music_artists(artist), music_title(title), album, times, skipped))
    return out


def music_counts(plays):
    """{artist: [plays, skips]}, the artist's name as most often written."""
    counts, names = {}, {}
    for _, _, _, artists, _, _, times, skipped in plays:
        for a in artists:
            k = fold(a)
            names.setdefault(k, {})[a] = names.get(k, {}).get(a, 0) + 1
            c = counts.setdefault(k, [0, 0])
            c[0] += times
            c[1] += 1 if skipped else 0
    return {max(names[k].items(), key=lambda kv: kv[1])[0]: c for k, c in counts.items()}


def top_artists(plays, n):
    counts = music_counts(plays)
    ranked = sorted(((a, c[0]) for a, c in counts.items() if c[0] > 0), key=lambda kv: -kv[1])
    return ranked[:n]


def music_taste(data, now, full=False):
    """What the user's listening says about their taste, as short lines:
    favourite artists, lately (new ones marked), and with `full` the top
    tracks, around this hour, often skipped and the players used."""
    plays = music_plays(data)
    if not any(not p[7] for p in plays):
        return []
    lines = []
    fav = top_artists(plays, 10 if full else 8)
    first = min(p[0] for p in plays)
    span = max(1, round((now - first) / 86400))
    lines.append(f"Favourite artists (last {span} days): " + ", ".join(f"{a} ({n})" for a, n in fav))
    recent_since = now - 14 * 86400
    recent = [p for p in plays if p[0] >= recent_since]
    before = {fold(a) for p in plays if p[0] < recent_since and not p[7] for a in p[3]}
    lately = top_artists(recent, 6)
    if lately and span > 14:
        new = [a for a, _ in lately if fold(a) not in before]
        lines.append("Lately (14 days): " + ", ".join(a for a, _ in lately)
                     + (f"; new to them: {', '.join(new)}" if new else ""))
    if not full:
        return lines
    tracks, names = {}, {}
    for _, _, _, artists, title, _, times, skipped in plays:
        if skipped or not artists:
            continue
        k = (fold(title), fold(artists[0]))
        tracks[k] = tracks.get(k, 0) + times
        names[k] = f"{title} – {artists[0]}"
    top = sorted(tracks.items(), key=lambda kv: -kv[1])[:8]
    if top:
        lines.append("Most played tracks: " + "; ".join(f"{names[k]} ({n})" for k, n in top))
    hour = time.localtime(now).tm_hour
    around, days = [], {}
    for p in plays:
        lt = time.localtime(p[0])
        gap = min(abs(lt.tm_hour - hour), 24 - abs(lt.tm_hour - hour))
        if gap <= 1 and not p[7]:
            around.append(p)
            for a in p[3]:
                days.setdefault(fold(a), set()).add(time.strftime("%Y-%m-%d", lt))
    usual = [(a, n) for a, n in top_artists(around, 8) if len(days.get(fold(a), ())) >= HABIT_MIN_DAYS][:5]
    if usual:
        lines.append(f"Around this hour ({hour:02d}h) they usually play: " + ", ".join(a for a, _ in usual))
    skipped = [(a, c) for a, c in music_counts(plays).items() if c[1] >= 3 and c[1] >= 2 * c[0]]
    if skipped:
        skipped.sort(key=lambda kv: -kv[1][1])
        lines.append("Often skipped: " + ", ".join(f"{a} ({c[1]} skips, {c[0]} plays)" for a, c in skipped[:5]))
    players = {}
    for p in plays:
        players[p[2]] = players.get(p[2], 0) + p[1]
    total = sum(players.values()) or 1
    lines.append("Listens on: " + ", ".join(f"{player_label(k)} {round(100 * v / total)}%"
                                             for k, v in sorted(players.items(), key=lambda kv: -kv[1])))
    lines.append(f"{sum(p[6] for p in plays)} plays and {sum(1 for p in plays if p[7])} skips recorded "
                 "(artists and tracks from the players; genres are for you to infer from the artists).")
    return lines


def music_digest(cfg, now=None, tool=True):
    """The line of the memory digest about the user's music (`tool`: the
    reader has the `habits` tool for more)."""
    if not music_on(cfg) or cfg.get("habitsAgents", "digest") == "off":
        return ""
    if now is None:
        return _digest_memo(f"music:{tool}", cfg, None, lambda: _music_digest(cfg, None, tool))
    return _music_digest(cfg, now, tool)


def _music_digest(cfg, now=None, tool=True):
    lines = music_taste(read_habits(), now or time.time())
    if not lines:
        return ""
    return ("The user's music taste (from what they play, on any player"
            + ("; `habits` what=music for more" if tool else "") + "): " + ". ".join(lines) + ".")


def music_clear():
    """The plays forgotten, the rest of the habits kept."""
    with Habits() as h:
        h.data["plays"] = []  # and those in the log: read in, then emptied
        h.save()


class HabitRecorder:
    """The user's focus and windows, from niri's event stream."""

    def __init__(self, cfg):
        self.cfg = cfg
        self.windows = {}  # niri id -> {"app", "private"}
        self.focused = None
        self.span = None  # [start, app]: the focus now
        self.pending = []  # records not appended yet
        self.ready = False  # the first WindowsChanged is the state, not new windows
        self.ids = {}  # niri app_id -> desktop id
        self.theme = None
        self.theme_mtime = None
        self.rank = None  # the launcher's ranking as last written
        self.own_opens = {}  # app -> until: opened by the habits, not the user

    def recording(self, now):
        return not habits_paused() and not screen_locked() and not agent_acting(now)

    def stop_times(self):
        """When recording may have stopped: the lock, the pause, an agent's
        last action. The recorder sleeps between niri's events, so a span
        ends then, not when it wakes up."""
        base = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
        out = []
        for path in (os.path.join(base, "nixbook-shell-locked"), habits_paused_flag()):
            try:
                out.append(os.stat(path).st_mtime)
            except OSError:
                pass
        last = (read_state().get("last") or {}).get("time", 0) / 1000
        if last:
            out.append(last)
        return out

    def app_of(self, app_id):
        if app_id not in self.ids:
            self.ids[app_id] = desktop_for_app(app_id, applications()) or app_id
        return self.ids[app_id]

    def window(self, w, now, opened):
        app_id = w.get("app_id") or ""
        self.windows[w.get("id")] = info = {
            "app": self.app_of(app_id),
            "private": habit_private(self.cfg, app_id, w.get("title")),
        }
        if opened and self.ready and not info["private"] and self.recording(now) \
                and self.own_opens.get(info["app"], 0) < now:
            self.pending.append({"o": [int(now), info["app"]]})
        if w.get("is_focused"):
            self.focused = w.get("id")

    def handle(self, ev, now):
        if "WindowsChanged" in ev:
            before = self.windows
            self.windows = {}
            for w in ev["WindowsChanged"].get("windows") or []:
                self.window(w, now, w.get("id") not in before)
            self.ready = True
        elif "WindowOpenedOrChanged" in ev:
            w = ev["WindowOpenedOrChanged"].get("window") or {}
            self.window(w, now, w.get("id") not in self.windows)
        elif "WindowClosed" in ev:
            wid = ev["WindowClosed"].get("id")
            self.windows.pop(wid, None)
            if self.focused == wid:
                self.focused = None
        elif "WindowFocusChanged" in ev:
            self.focused = ev["WindowFocusChanged"].get("id")
        self.refresh(now)

    def refresh(self, now):
        w = self.windows.get(self.focused)
        recording = self.recording(now)
        app = w["app"] if w and not w["private"] and recording else None
        if self.span and self.span[1] == app:
            if now - self.span[0] >= HABIT_CHECKPOINT:
                # A long one, in pieces: a crash loses half an hour at most.
                self.close(now)
                self.span = [now, app]
            return
        end = now
        if self.span and not recording:
            end = min([t for t in self.stop_times() if self.span[0] < t < now] or [now])
        self.close(end)
        if app:
            self.span = [now, app]

    def close(self, now):
        if self.span:
            start, app = self.span
            if now - start >= HABIT_MIN_SPAN:
                self.pending.append({"s": [int(start), int(now), app]})
            self.span = None

    def read_theme(self):
        """The theme in the shell's config.json, read again only when the
        file changed."""
        path = os.path.join(xdg("XDG_CONFIG_HOME", "~/.config"), "nixbook-shell", "config.json")
        try:
            mtime = os.stat(path).st_mtime_ns
            if mtime == self.theme_mtime:
                return self.theme
            with open(path, encoding="utf-8") as f:
                appearance = json.load(f).get("appearance") or {}
            self.theme_mtime = mtime
            theme = appearance.get("theme") or ""
            variant = ((appearance.get(theme) or {}).get("variant") or "") if theme else ""
            return f"{theme}/{variant}" if theme else None
        except (OSError, ValueError, AttributeError):
            return None

    def flush(self, now):
        """The records since the last time, appended to habits.log (nothing
        when nothing happened), with a theme the user chose."""
        theme = self.read_theme()
        if theme and self.theme and theme != self.theme and self.recording(now):
            self.pending.append({"e": [int(now), "theme", theme]})
        self.theme = theme or self.theme
        records, self.pending = self.pending, []
        habits_append(records)

    def write_rank(self, data, now):
        """habits-rank.json, for the launcher, rewritten only when it
        changed (the launcher re-sorts on each write): the apps used around
        this hour (0-1) and the apps opened after each app, by desktop id;
        `ids` maps niri's app ids to desktop ids."""
        usual = usual_apps(data, now)[:12]
        top = usual[0][1] if usual else 1
        doc = {
            "now": {a: round(s / top, 1) for a, s in usual},
            "after": transitions(data),
            "ids": {k: v for k, v in self.ids.items() if k and k != v},
        }
        path = habits_rank_path()
        if doc == self.rank and os.path.exists(path):
            return
        fd = os.open(path + ".tmp", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(doc, f)
        os.replace(path + ".tmp", path)
        self.rank = doc


def habits_notify(title, body, icon, action=None):
    """A notification (icon: a freedesktop icon name, not a Material
    Symbols one: those draw as the missing icon); with an action, its label: True once clicked (waits
    for it, so call it in a thread)."""
    if not shutil.which("notify-send"):
        return False
    argv = ["notify-send", "-a", "Usage habits", "-i", icon]
    if action:
        argv += ["-A", f"yes={action}"]
    try:
        out = subprocess.run(argv + [title, body], capture_output=True, text=True,
                             timeout=600 if action else 10)
    except (OSError, subprocess.TimeoutExpired):
        return False
    return out.stdout.strip() == "yes"


def habits_jobs(cfg, rec, data, now):
    """What the habits do on their own, each at most once a day (the
    report once a week): the weekly report, the theme hint, the apps that
    open at their usual time."""
    lt = time.localtime(now)
    today = time.strftime("%Y-%m-%d", lt)
    sent = data.get("sent") or {}
    marks = {}

    week = time.strftime("%G-W%V", lt)
    if cfg.get("habitsWeeklyReport", True) and sent.get("report") != week and lt.tm_hour >= 9 \
            and data["spans"] and now - data["spans"][0][0] >= 6 * 86400 and rec.span:
        marks["report"] = week
        report = week_report(data, now)
        threading.Thread(target=habits_notify, daemon=True,
                         args=("Your week on this computer", report, "office-chart-bar")).start()

    mode = cfg.get("habitsTheme", "suggest")
    hint = theme_hint(data, now) if mode in ("suggest", "auto") and rec.span else None
    if hint and hint != rec.theme and sent.get("theme") != today:
        marks["theme"] = today
        theme, _, variant = hint.partition("/")
        label = f"{theme} ({variant})" if variant else theme

        def switch(ask):
            if not ask or habits_notify(f"Switch to {label}?",
                                        "You usually switch to it around this time.", "preferences-desktop-theme", "Switch"):
                try:
                    qs_ipc("call", "--", "theme", "set", theme, variant)
                except ToolError as e:
                    log(f"habits: theme: {e}")
                else:
                    # Not a choice of the user's: it mustn't feed the hint.
                    rec.theme = hint
                    if not ask:
                        habits_notify(f"Switched to {label}", "As you usually do around this time "
                                      "(Settings > Desktop agents > Usage habits).", "preferences-desktop-theme")
        threading.Thread(target=switch, args=(mode == "suggest",), daemon=True).start()

    opened = dict(sent.get("open") or {})
    running = {w["app"] for w in rec.windows.values()}
    for app in cfg.get("habitsOpenAtUsualTime") or []:
        entry = applications().get(app)
        if not entry or entry.get("Terminal") == "true" or app in running or opened.get(app) == today \
                or not rec.span or not usually_opened_now(data, app, now):
            continue
        opened[app] = today
        rec.own_opens[app] = now + 20
        try:
            run(["niri", "msg", "action", "spawn", "--", *exec_argv(entry)])
            habits_notify(f"Opened {entry.get('Name') or app}", "You usually open it around this time.", "chronometer")
        except ToolError as e:
            log(f"habits: open {app}: {e}")
    if opened != (sent.get("open") or {}):
        marks["open"] = opened

    if marks:
        with Habits() as h:
            h.data["sent"].update(marks)
            h.save()


def habits_watch(cfg):
    """The recorder (the nixbook-habits user service): niri's event stream
    read in a thread, the main loop asleep until an event or HABIT_WAKE;
    the records appended once a minute at most, the launcher's ranking and
    the notifications every HABIT_JOBS_EVERY, habits.json compacted daily.
    The players' tracks (music taste) come the same way, from playerctl."""
    if not habits_on(cfg):
        log("usage habits are off (Settings > Desktop agents > Usage habits)")
        return 0
    rec = HabitRecorder(cfg)
    music = MusicTracker(cfg)
    rec.theme = rec.read_theme()
    events = queue.Queue()
    stop = threading.Event()
    procs = []

    def stream():
        while not stop.is_set():
            try:
                proc = subprocess.Popen(["niri", "msg", "-j", "event-stream"], stdout=subprocess.PIPE,
                                        stderr=subprocess.DEVNULL, text=True)
            except OSError as e:
                log(f"habits: niri: {e}")
                time.sleep(5)
                continue
            procs.append(proc)
            for line in proc.stdout:
                try:
                    events.put(json.loads(line))
                except ValueError:
                    pass
            proc.wait()
            procs.remove(proc)
            time.sleep(2)

    def players():
        # Every player's track and status as they change; a blank line when
        # a player goes away.
        while not stop.is_set():
            try:
                proc = subprocess.Popen(["playerctl", "--all-players", "--follow", "metadata",
                                         "--format", MUSIC_FORMAT], stdout=subprocess.PIPE,
                                        stderr=subprocess.DEVNULL, text=True)
            except OSError as e:
                log(f"habits: playerctl: {e}")
                stop.wait(300)
                continue
            procs.append(proc)
            for line in proc.stdout:
                events.put(("music", line))
            proc.wait()
            procs.remove(proc)
            stop.wait(5)

    def on_term(*_):
        stop.set()
        events.put(None)

    signal.signal(signal.SIGTERM, on_term)
    signal.signal(signal.SIGINT, on_term)
    threading.Thread(target=stream, daemon=True).start()
    if music_on(cfg):
        threading.Thread(target=players, daemon=True).start()
    last_flush = time.time()
    last_jobs, last_hour, compacted = 0.0, None, None
    while not stop.is_set():
        try:
            ev = events.get(timeout=HABIT_WAKE)
        except queue.Empty:
            ev = None
        now = time.time()
        if isinstance(ev, tuple):
            if ev[1].strip():
                rec.pending += music.line(ev[1], now)
            else:
                try:
                    left = run(["playerctl", "--list-all"], check=False, timeout=5).stdout
                    rec.pending += music.gone({music.name(p) for p in left.split()} - {None}, now)
                except ToolError:
                    pass
        elif isinstance(ev, dict):
            rec.handle(ev, now)
        else:
            rec.refresh(now)
        try:
            if now - last_flush >= 60:
                last_flush = now
                rec.pending += music.stale(now)
                rec.flush(now)
            hour = time.localtime(now).tm_hour
            if now - last_jobs >= HABIT_JOBS_EVERY or hour != last_hour:
                last_jobs, last_hour = now, hour
                today = time.strftime("%Y-%m-%d", time.localtime(now))
                if compacted != today:
                    compacted = today
                    habits_compact(cfg, now)
                data = read_habits()
                rec.write_rank(data, now)
                habits_jobs(cfg, rec, data, now)
        except (OSError, ValueError, KeyError, TypeError) as e:
            log(f"habits: {e}")
    for proc in list(procs):
        proc.terminate()
    rec.close(time.time())
    rec.pending += music.close(time.time())
    try:
        rec.flush(time.time())
    except (OSError, ValueError):
        pass
    return 0


def habits_command(cfg, argv):
    """Usage habits, for the user (Settings > Desktop agents > Usage habits)
    and the shell (the launcher's aliases)."""
    sub = argv[0] if argv else "status"
    now = time.time()
    if sub == "watch":
        return habits_watch(cfg)
    if sub == "cue" and len(argv) in (2, 3):
        # A cue the shell saw (audio output, Wi-Fi, a monitor, the power
        # cable, unlocking): what learned routines start from. Device and
        # network names only.
        if argv[1] in CUE_WORDS and habits_on(cfg) and not habits_paused():
            name = clean_text(argv[2], 60) if len(argv) == 3 else ""
            habits_append([{"e": [int(now), "cue", f"{argv[1]}:{name}"]}])
        return 0
    if sub == "on":
        os.makedirs(habits_dir(), mode=0o700, exist_ok=True)
        with open(habits_enabled_flag(), "w", encoding="utf-8") as f:
            f.write("on\n")
        habits_unit("start")
        print("usage habits on")
        return 0
    if sub == "off":
        if habits_nix(cfg):
            print("usage habits are on in the Nix configuration (desktopMcp.habits.enable)", file=sys.stderr)
            return 1
        try:
            os.unlink(habits_enabled_flag())
        except FileNotFoundError:
            pass
        habits_unit("stop")
        if "--forget" in argv:
            habits_clear()
        print("usage habits off" + (", everything recorded forgotten" if "--forget" in argv else ""))
        return 0
    if sub == "toggle":
        sub = "resume" if habits_paused() else "pause"
    if sub == "pause":
        os.makedirs(habits_dir(), mode=0o700, exist_ok=True)
        with open(habits_paused_flag(), "w", encoding="utf-8") as f:
            f.write("paused\n")
        print("usage habits paused: nothing is recorded")
        return 0
    if sub == "resume":
        try:
            os.unlink(habits_paused_flag())
        except FileNotFoundError:
            pass
        print("usage habits recording")
        return 0
    if sub == "status":
        data = read_habits()
        first = data["spans"][0][0] if data["spans"] else None
        print(json.dumps({
            "enabled": habits_on(cfg), "nix": habits_nix(cfg), "paused": habits_paused(),
            "agents": cfg.get("habitsAgents", "digest"),
            "keepDays": cfg.get("habitsKeepDays", 28), "theme": cfg.get("habitsTheme", "suggest"),
            "openAtUsualTime": cfg.get("habitsOpenAtUsualTime") or [],
            "days": round((now - first) / 86400, 1) if first else 0,
            "now": habits_now(data, now), "report": week_report(data, now) if first else "",
            "musicOn": music_on(cfg), "musicKeepDays": cfg.get("habitsMusicKeepDays", 365),
            "music": music_taste(data, now, full=True),
            "path": habits_path(),
        }, ensure_ascii=False))
        return 0
    if sub == "show":
        print(json.dumps(read_habits(), ensure_ascii=False))
        return 0
    if sub == "now":
        print("\n".join(habits_now(read_habits(), now)) or "not enough usage recorded yet")
        return 0
    if sub == "report":
        days = int(argv[1]) if len(argv) > 1 and argv[1].isdigit() else 7
        print(week_report(read_habits(), now, days))
        return 0
    if sub == "day":
        date = argv[1] if len(argv) > 1 else time.strftime("%Y-%m-%d", time.localtime(now))
        print(day_timeline(read_habits(), date))
        return 0
    if sub == "digest":
        print("\n".join(x for x in (habits_digest(cfg, now), music_digest(cfg, now)) if x))
        return 0
    if sub == "music":
        print("\n".join(music_taste(read_habits(), now, full=True)) or "no music recorded yet")
        return 0
    if sub == "music-clear":
        music_clear()
        print("forgot the music listened to")
        return 0
    if sub == "alias" and len(argv) == 3:
        word = learn_alias(cfg, argv[1], argv[2])
        if word:
            print(f"learned alias {word!r} -> {argv[2]}")
        return 0
    if sub == "clear":
        habits_clear()
        print("cleared the usage habits")
        return 0
    print(USAGE, end="", file=sys.stderr)
    return 2


def habits_unit(action):
    """The recorder started or stopped now (it also starts with the session
    while on)."""
    try:
        run(["systemctl", "--user", action, HABIT_UNIT], check=False, timeout=20)
    except ToolError as e:
        log(f"habits: {e}")


def habits_clear():
    with Habits():  # not halfway through a write
        for path in (habits_path(), habits_log_path(), habits_rank_path()):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass


# -- personal memory -------------------------------------------------------------
# What the user told agents about their life, so the next conversation
# knows it: one entry per subject ("japan", "work", "Lan (sister)"), a few
# condensed facts each, merged by the agent as things change, never a
# transcript. Only what bears on a conversation reaches the model: when an
# agent connects, the profile (who the user is), events coming up or just
# past, the subjects talked about lately and the other subjects by name
# only; the entries about a message in full when it mentions them (the
# shell's AI chat sends them with the message, `personal context`; other
# clients get them with the next reply). recall_about_user has the rest.
# ~/.local/state/nixbook-shell/personal-memory.json, private, and apart from
# the desktop memory: Settings > Desktop agents > About you, or
# `nixbook-desktop-mcp personal`.

PERSONAL_TOPIC_MAX = 40
PERSONAL_TEXT_MAX = 400
# profile: who the user is (always sent, so few and short); person: someone
# in their life; event: something that happened or will, on `date`; topic:
# an interest, a project, a plan, a conversation's subject.
PERSONAL_KINDS = ("profile", "person", "event", "topic")
PERSONAL_DATE = r"\d{4}(-\d{2}(-\d{2})?)?"
# Kept like a person keeps memories: each entry has an importance (1-5,
# given by the memory pass; 3 when an agent saves it, 5 the profile).
# What mattered little (1-2) is tentative until it comes up again: kept but
# not sent, dropped after TENTATIVE_DAYS. What comes up again is held more
# firmly (`mentions`; the 3rd and 6th raise its importance). Unused entries
# fade: forgotten after FADE_DAYS[importance] without being updated or
# used; 4-5 and the profile never fade.
PERSONAL_IMPORTANCE = 3
TENTATIVE_MAX = 2
TENTATIVE_DAYS = 60
FADE_DAYS = {1: 90, 2: 180, 3: 365}


def personal_path():
    return os.path.join(xdg("XDG_STATE_HOME", "~/.local/state"), "nixbook-shell", "personal-memory.json")


def empty_personal():
    return {"version": 1, "entries": []}


class PersonalMemory(Memory):
    path = staticmethod(personal_path)
    empty = staticmethod(empty_personal)

    def migrate(self):
        if not isinstance(self.data.get("entries"), list):
            self.data["entries"] = []


def read_personal():
    try:
        with PersonalMemory() as m:
            return m.data["entries"]
    except OSError:
        return []


def importance(e):
    return 5 if e.get("kind") == "profile" else int(e.get("importance", PERSONAL_IMPORTANCE))


def faded(e, now):
    """Whether an entry is forgotten by now: tentative and never brought up
    again, or unused for longer than its importance holds it."""
    if e.get("tentative"):
        return now - e.get("created", now) > TENTATIVE_DAYS * 86400
    days = FADE_DAYS.get(importance(e))
    touched = max(e.get("updated", 0), e.get("used", 0))
    return bool(days) and now - touched > days * 86400


def bring_up(e, now):
    """The entry came up again: held more firmly (no longer tentative, the
    3rd and 6th time a step more important, its fading started over)."""
    e["mentions"] = e.get("mentions", 1) + 1
    e.pop("tentative", None)
    e["used"] = now
    if e["mentions"] in (3, 6) and e.get("kind") != "profile":
        level = importance(e)
        e["importance"] = max(level, min(level + 1, 4))


def fade_personal(now=None):
    """Forgets the entries that faded: the ids."""
    now = now or time.time()
    with PersonalMemory() as m:
        gone = [e["id"] for e in m.data["entries"] if faded(e, now)]
        if gone:
            m.data["entries"] = [e for e in m.data["entries"] if e["id"] not in gone]
            m.save()
    return gone


def count_entry_uses(ids):
    if not ids:
        return
    try:
        with PersonalMemory() as m:
            now = int(time.time())
            for e in m.data["entries"]:
                if e["id"] in ids:
                    e["uses"] = e.get("uses", 0) + 1
                    e["used"] = now
            m.save()
    except (OSError, ValueError, KeyError, TypeError):
        pass


def date_span(value):
    """The days a date covers: 2027-04-03, all April 2027, all 2027."""
    try:
        parts = [int(p) for p in (value or "").split("-")]
        if len(parts) == 3:
            start = datetime.date(*parts)
            return start, start
        if len(parts) == 2:
            start = datetime.date(parts[0], parts[1], 1)
            nxt = datetime.date(parts[0] + parts[1] // 12, parts[1] % 12 + 1, 1)
            return start, nxt - datetime.timedelta(days=1)
        if len(parts) == 1:
            return datetime.date(parts[0], 1, 1), datetime.date(parts[0], 12, 31)
    except (ValueError, TypeError):
        pass
    return None


def entry_line(e, limit=PERSONAL_TEXT_MAX, weight=False):
    label = e["topic"] + (f", {e['date']}" if e.get("date") else "")
    kind = e.get("kind", "topic") + (f", i{importance(e)}" if weight else "") + (", tentative" if e.get("tentative") else "")
    return f"- [{e['id']}] {label} ({kind}): {short(e['text'], limit)}"


def personal_matches(entries, query, exclude=(), limit=3, tentative=False):
    """The entries a query is about; not the tentative ones, unless asked
    (they cost tokens in every conversation for what mattered little)."""
    return [e for e in rank_notes(entries, query)
            if e["id"] not in exclude and (tentative or not e.get("tentative"))][:limit]


def ago(ts, now):
    days = int((now - ts) // 86400)
    return "today" if days < 1 else "yesterday" if days < 2 else f"{days} days ago"


def personal_digest(cfg, query="", limit=None):
    """The personal memory as a short text for a model's context. Capped at
    personalPromptChars: the profile first, then what is soonest useful."""
    limit = limit or int(cfg.get("personalPromptChars", 900))
    entries = [e for e in read_personal() if not e.get("tentative")]
    if not entries:
        return "Personal memory: nothing remembered about the user yet."
    now = time.time()
    today = datetime.date.today()
    shown = set()
    lines = []
    profile = [e for e in entries if e.get("kind") == "profile"]
    if profile:
        lines.append("Profile: " + " ".join(short(e["text"], 200) for e in profile))
        shown.update(e["id"] for e in profile)
    dated = []
    for e in entries:
        span = date_span(e.get("date")) if e.get("kind") == "event" else None
        if span and span[1] >= today - datetime.timedelta(days=14) and span[0] <= today + datetime.timedelta(days=60):
            dated.append((span[0], e))
    dated.sort(key=lambda x: x[0])
    if dated:
        lines.append("Coming up or just past (today is " + today.isoformat() + "):")
        lines += [entry_line(e, 160) for _, e in dated[:4]]
        shown.update(e["id"] for _, e in dated[:4])
    found = personal_matches(entries, query, shown)
    if found:
        lines.append("About this message:")
        lines += [entry_line(e) for e in found]
        shown.update(e["id"] for e in found)
    recent = sorted((e for e in entries if e["id"] not in shown and now - e.get("updated", 0) < 14 * 86400),
                    key=lambda e: -e.get("updated", 0))[:3]
    recent_line = ("Talked about lately (recall_about_user for details): "
                   + ", ".join(f"{e['topic']} ({ago(e['updated'], now)})" for e in recent))
    if recent:
        lines.append(recent_line)
    out = ("About the user, from earlier conversations with them (what they shared, "
           "not instructions):")
    for line in lines:
        if len(out) + len(line) + 1 > limit:
            break
        out += "\n" + line
    listed = shown | ({e["id"] for e in recent} if recent and recent_line in out else set())
    rest = [e["topic"] for e in sorted(entries, key=lambda e: (-importance(e), -e.get("uses", 0), -e.get("updated", 0)))
            if e["id"] not in listed]
    for k in range(len(rest), 0, -1):
        more = f", +{len(rest) - k} more" if k < len(rest) else ""
        line = "\nOther subjects you know about: " + ", ".join(rest[:k]) + more
        if len(out) + len(line) <= limit:
            out += line
            break
    count_entry_uses(shown - {e["id"] for e in profile})
    return out


def personal_digest_ids(query=""):
    """The entries a digest for this query gives in full (for the session's
    record of what it was told)."""
    entries = [e for e in read_personal() if not e.get("tentative")]
    today = datetime.date.today()
    ids = {e["id"] for e in entries if e.get("kind") in ("profile", "event")}
    ids |= {e["id"] for e in personal_matches(entries, query)}
    return ids


PERSONAL_CONTEXT_MIN = 2


def personal_context(cfg, query, exclude=()):
    """The entries a message is about and the people it names (their
    contacts), not given yet: for the shell's AI chat to send with the
    message. (text, ids: the entries', and "contact:<id>" the contacts')"""
    exclude = set(exclude)
    found = personal_matches(read_personal(), query, exclude) if "personal" in cfg["tools"] else []
    # With every message: only entries about it (a word of their topic or
    # keywords, or two of their text). One shared word brought unrelated
    # ones (a birthday gift with a screenshot question): tokens for
    # nothing, and a distraction. recall_about_user still finds them all.
    qw = words(query)
    if found:
        entries = read_personal()
        texts = {e["id"]: set(words(e.get("text", ""))) for e in entries}

        def telling(e):
            # One word of its text, said exactly and rare among the entries
            # ("Kyoto"): about it; one prefix-close or common ("shortcut"
            # for "short", "take"): not.
            exact = [w for w in qw if len(w) >= 4 and w in texts.get(e["id"], ())]
            return any(sum(1 for t in texts.values() if w in t) <= 2 for w in exact)
        found = [e for e in found if note_score(e, qw) >= PERSONAL_CONTEXT_MIN or telling(e)]
    people, people_ids = people_context(cfg, query, {i[8:] for i in exclude if i.startswith("contact:")})
    parts = []
    if found:
        count_entry_uses({e["id"] for e in found})
        parts.append("(Memory about the user that may bear on this message, from earlier conversations:\n"
                     + "\n".join(entry_line(e) for e in found) + ")")
    if people:
        parts.append(people)
    return "\n\n".join(parts), [e["id"] for e in found] + [f"contact:{i}" for i in people_ids]


PERSONAL_INSTRUCTIONS = (
    "Personal memory: you remember the user across conversations. When they "
    "tell you something lasting about their life (an event past or planned, a "
    "plan, someone close to them, a preference, a project, a decision, what "
    "matters to them) or a conversation reaches something worth keeping (a "
    "choice made, a conclusion), save the meaningful part with "
    "remember_about_user: a few condensed facts in plain words, not a "
    "transcript or a summary of what you said; absolute dates (\"2027-04\", "
    "not \"next spring\"). One entry per subject: the entries below and "
    "recall_about_user give their ids; update one (its id, the old and new "
    "facts merged, what no longer holds dropped) rather than adding another. "
    "Don't save small talk, one-off requests, what is only true today, "
    "desktop how-tos (remember is for those), or secrets (passwords, numbers "
    "of cards or accounts); health and other sensitive matters only when "
    "they ask. Name a person's entry \"Name (relation)\": it is also kept in "
    "the notes of their contact. When the user names someone, work out who "
    "before acting: the people sent with their message (their contacts, "
    "with what you remember about them) first, else search the contacts "
    "(contacts list, the name as query; a nickname or misspelling may need "
    "a shorter query) and recall_about_user; when several match or none "
    "does, ask which one rather than guess, and once you know who they are "
    "to the user (\"my sister\", \"Tuan from work\"), remember it in their "
    "entry, so next time you know. Save without asking and without more than "
    "a few words about it; when they ask you to remember or forget something, do it; when they "
    "ask what you know about them, recall it. Use what you know naturally, "
    "don't recite it."
)


def personal_injected():
    # The shell's AI chat sends the entries about each message itself.
    return os.environ.get("NIXBOOK_DESKTOP_MCP_PERSONAL") == "shell"


def personal_task_note(ctx, query):
    if not query or personal_injected():
        return None
    notes = []
    if "personal" in ctx.cfg["tools"]:
        found = personal_matches(read_personal(), query, ctx.entries_shown)
        if found:
            ctx.entries_shown.update(e["id"] for e in found)
            count_entry_uses({e["id"] for e in found})
            notes.append("Memory about the user for this message:\n" + "\n".join(entry_line(e) for e in found))
    people, ids = people_context(ctx.cfg, query, {i[8:] for i in ctx.entries_shown if i.startswith("contact:")})
    if people:
        ctx.entries_shown.update(f"contact:{i}" for i in ids)
        notes.append(people)
    return "\n\n".join(notes) or None
