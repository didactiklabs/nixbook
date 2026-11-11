# Part of nixbook-desktop-mcp (see ../desktop-mcp.py). The parts run in
# order in one module namespace, as one file: a name defined in any part
# is visible in every other, and tests may replace any function.
#
# Secrets kept out of what is shown, and Find it (find_anything).

# Letters NFKD leaves alone, folded by hand (find_anything's time words).
MATCH_LETTERS = str.maketrans({"đ": "d", "ß": "ss", "ø": "o", "æ": "ae", "œ": "oe", "ł": "l", "ı": "i"})

# Secrets in a file's text or a link, blacked out before anything is shown.
SECRET_PATTERNS = (
    (re.compile(r"-----BEGIN ([A-Z0-9 ]*PRIVATE KEY[A-Z ]*|PGP PRIVATE KEY BLOCK)-----.*?(-----END [A-Z0-9 ]*-----|\Z)",
                re.S), "[private key redacted]"),
    (re.compile(r"(?im)^(\s*(?:proxy-)?authorization\s*:\s*).+$"), r"\1[redacted]"),
    (re.compile(r"(?i)\b((?:proxy-)?authorization\s*[:=]\s*)(?:(?:bearer|basic|token|digest)\s+)?[^\s'\",;]+"),
     r"\1[redacted]"),
    (re.compile(r"(?i)\b(bearer)\s+[A-Za-z0-9._~+/=\-]{12,}"), r"\1 [redacted]"),
    (re.compile(r"\bsk-(?:ant-|proj-|live-|test-)?[A-Za-z0-9_\-]{16,}"), "[key redacted]"),
    (re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})"), "[token redacted]"),
    (re.compile(r"\b(?:glpat-[A-Za-z0-9_\-]{20,}|xox[abpors]-[A-Za-z0-9\-]{10,}|AIza[0-9A-Za-z_\-]{35}|"
                r"hf_[A-Za-z0-9]{30,}|npm_[A-Za-z0-9]{30,})"), "[token redacted]"),
    (re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"), "[AWS key redacted]"),
    (re.compile(r"\beyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}"), "[JWT redacted]"),
    (re.compile(r"(?i)\b([a-z][a-z0-9+.\-]*://[^/\s:@]+):([^@\s/]+)@"), r"\1:[redacted]@"),
    (re.compile(r"(?i)\b([\w.\-]*(?:password|passwd|passphrase|token|secret|api[_\-]?key|apikey|access[_\-]?key|"
                r"private[_\-]?key|client[_\-]?secret)[\w.\-]*)([\"']?\s*[=:]\s*)(?!\[)(\"[^\"\n]*\"|'[^'\n]*'|[^\s,;&\"']+)"),
     r"\1\2[redacted]"),
)


def redact_secrets(value):
    """What a terminal or a file showed, its secrets blacked out (before the
    privacy mask): private keys, API keys and tokens, JWTs, Authorization
    headers, password=/token=/secret=/api_key= values, URL credentials."""
    value = str(value or "")
    for pat, repl in SECRET_PATTERNS:
        value = pat.sub(repl, value)
    return value


def home_short(path):
    for home in (os.path.expanduser("~"), os.path.realpath(os.path.expanduser("~"))):
        if path == home or path.startswith(home + os.sep):
            return "~" + path[len(home):]
    return path


def safe_home_path(path):
    """The real path of PATH when it is the home or in it, and not in a
    hidden folder of it (settings, keys, logins: as safe_folder); else a
    ToolError."""
    home = os.path.realpath(os.path.expanduser("~"))
    real = os.path.realpath(os.path.expanduser(str(path)))
    if real != home and not real.startswith(home + os.sep):
        raise ToolError(f"refused: {path} isn't in the user's home")
    if real[len(home) + 1:].startswith("."):
        raise ToolError(f"refused: {path} is in a hidden folder of the home (settings, keys, logins)")
    return real


FIND_KINDS = ("files", "pages", "bookmarks", "clipboard", "notifications", "chats")
FIND_MAX = 30
# Words that only say what kind of thing is looked for: a boost for that
# kind, not words to find in it (folded, as words() gives them).
FIND_HINTS = {
    "files": "file files fichier fichiers datei dateien tep download downloaded downloads telecharge telecharges "
             "telechargement telechargements heruntergeladen download tai xuong document documents dokument "
             "dokumente doc screenshot screenshots capture captures bildschirmfoto photo photos picture pictures "
             "image images bild bilder anh",
    "pages": "link links lien liens url site website page pages seite webseite trang web article visited visite "
             "besucht",
    "bookmarks": "bookmark bookmarks bookmarked favori favoris marque page lesezeichen dau",
    "clipboard": "copied copy clipboard copie copiee copies presse papiers kopiert kopierte zwischenablage sao chep",
    "notifications": "sent send texted message messages envoye envoyee envoyes envoyees geschickt schickte "
                     "gesendet nachricht nachrichten gui tin nhan notification notifications benachrichtigung",
    "chats": "chat chats conversation conversations asked dai discussion gesprach unterhaltung tro chuyen",
}
FIND_HINT_OF = {w: kind for kind, ws in FIND_HINTS.items() for w in ws.split()}
# File types said by name ("the PDF"): files of that type only.
FIND_EXTS = {"pdf": ("pdf",), "png": ("png",), "jpg": ("jpg", "jpeg"), "jpeg": ("jpg", "jpeg"),
             "docx": ("docx", "doc", "odt"), "word": ("docx", "doc", "odt"), "odt": ("odt",),
             "xlsx": ("xlsx", "xls", "ods", "csv"), "excel": ("xlsx", "xls", "ods", "csv"), "csv": ("csv",),
             "pptx": ("pptx", "ppt", "odp"), "slides": ("pptx", "ppt", "odp", "pdf"), "zip": ("zip", "tar", "gz", "7z"),
             "mp4": ("mp4", "mkv", "webm", "mov"), "video": ("mp4", "mkv", "webm", "mov"),
             "mp3": ("mp3", "flac", "ogg", "m4a", "wav"), "txt": ("txt",), "markdown": ("md",), "md": ("md",)}
# The request's own words, never what is looked for.
FIND_SKIP = set(
    "find found where was were did done we our us have had saw seen see get got show give look looking "
    "remember recall again thing something stuff one about which who whose there here then just yet "
    "ou etait etaient trouve trouver retrouve retrouver retrouvez cherche chercher quoi quel quelle quels quelles "
    "avons nous on ai vu eu ce cette ces qui que qu chose truc encore "
    "wo war waren haben hatte hatten wir uns habe ich finden finde gefunden zeig zeige suche suchen welche welcher "
    "welches was etwas nochmal "
    "tim thay dau da chung gi cai kia nao ay lai xem".split())
# Files never listed (keys, password stores, wallets) and folders never walked.
FIND_SECRET_FILE = re.compile(
    r"(^id_(rsa|dsa|ecdsa|ed25519)|\.(kdbx?|pem|key|p12|pfx|gpg|asc|age|ovpn|keystore|jks|wallet)$|"
    r"passw(or)?d|mot.de.passe|kennwort|credential|recovery.?codes?|backup.?codes?|(^|[\W_])(2fa|otp|secrets?)([\W_.]|$))",
    re.I)
FIND_SKIP_DIRS = {"node_modules", "__pycache__", "venv", "target", "result", "vendor", "dist", "build"}
FIND_TEXT_EXTS = {"txt", "md", "markdown", "csv", "tsv", "json", "org", "rst", "log", "html", "htm", "xml",
                  "yaml", "yml", "tex", "srt", "vtt", "ics"}
FIND_WALK_MAX = 4000      # files looked at, in all the folders
FIND_WALK_DEPTH = 3       # folders below each one walked
FIND_READ_MAX = 25        # files whose text is read, the newest first
FIND_READ_BYTES = 64000
FIND_PDF_MAX = 30 * 1024 * 1024
FIND_DEADLINE = 4.0       # seconds for the slow parts (reading text, Zen's history)
# A link carrying a key or a code: never given (as the smart clipboard).
FIND_KEYED_URL = re.compile(r"[?&#](token|key|apikey|api_key|access_token|code|sig|signature|secret|password|auth|"
                            r"session|sid|otp)=", re.I)
FIND_URL = re.compile(r"https?://[^\s<>\"'()\]]+")
_FIND_TEXT = {}           # (path, mtime_ns, size) -> its text (the helper keeps it between searches)
_FIND_BLOCKED = {}
_FIND_FOLD = None         # accented Latin letters -> plain ones, for the quick pass before note_score


def find_fold(value):
    """`value` lower-cased with the accents of Latin letters dropped (as
    words() folds them), quickly: str.translate, no NFKD."""
    global _FIND_FOLD
    if _FIND_FOLD is None:
        table = {}
        for code in [*range(0xC0, 0x250), *range(0x1E00, 0x1F00)]:
            c = chr(code)
            base = "".join(x for x in unicodedata.normalize("NFKD", c.lower()) if not unicodedata.combining(x))
            base = base.translate(MATCH_LETTERS)
            if base != c:
                table[code] = base
        _FIND_FOLD = table
    return value.lower().translate(_FIND_FOLD)
_FIND_LOCK = threading.Lock()

# Time words → a range. Weekdays, Monday first; folded (thứ hai → thu hai).
FIND_WEEKDAYS = (
    ("monday", "lundi", "montag", "thu hai"), ("tuesday", "mardi", "dienstag", "thu ba"),
    ("wednesday", "mercredi", "mittwoch", "thu tu"), ("thursday", "jeudi", "donnerstag", "thu nam"),
    ("friday", "vendredi", "freitag", "thu sau"), ("saturday", "samedi", "samstag", "thu bay"),
    ("sunday", "dimanche", "sonntag", "chu nhat"),
)


def _find_day(d, days=1):
    """[start, end) of `days` days from date d, local time (epoch seconds)."""
    start = datetime.datetime(d.year, d.month, d.day)
    return start.timestamp(), (start + datetime.timedelta(days=days)).timestamp()


def find_when(value, now=None):
    """The time a request names: ({from, to, label} or None, the request
    without those words). `now` (epoch seconds) for the tests."""
    now = time.time() if now is None else now
    today = datetime.date.fromtimestamp(now)
    s = fold(str(value or "")).translate(MATCH_LETTERS)
    iso = re.search(r"\b(\d{4})-(\d{2})-(\d{2})\b", s)
    if iso:
        try:
            d = datetime.date(int(iso.group(1)), int(iso.group(2)), int(iso.group(3)))
        except ValueError:
            d = None
        if d:
            a, b = _find_day(d)
            return {"from": a, "to": b, "label": d.isoformat()}, s[:iso.start()] + " " + s[iso.end():]
    s = " " + " ".join(re.findall(r"[a-z0-9]+", s)) + " "

    def hit(pattern):
        return re.search(r"(?<= )(?:" + pattern + r")(?= )", s)

    def out(a, b, label, m):
        return {"from": a, "to": min(b, now + 60), "label": label}, s[:m.start()] + " " + s[m.end():]

    yesterday = today - datetime.timedelta(days=1)
    monday = today - datetime.timedelta(days=today.weekday())
    first = today.replace(day=1)
    # Weekdays: "last Monday" the one before today; "Monday" the latest, today included.
    for i, names in enumerate(FIND_WEEKDAYS):
        alt = "|".join(names)
        back = (today.weekday() - i) % 7
        m = hit(rf"(?:last|past|previous) (?:{alt})|(?:{alt}) (?:dernier|passe)|(?:letzten|letzter|vergangenen|"
                rf"vorigen) (?:{alt})|(?:{alt}) tuan truoc")
        if m:
            d = today - datetime.timedelta(days=back or 7)
            return out(*_find_day(d), f"{names[0].capitalize()} {d.isoformat()}", m)
        m = hit(rf"(?:on |le |am |vao )?(?:{alt})")
        if m:
            d = today - datetime.timedelta(days=back)
            return out(*_find_day(d), f"{names[0].capitalize()} {d.isoformat()}", m)
    m = hit(r"(?:the )?day before yesterday|avant hier|vorgestern|hom kia")
    if m:
        return out(*_find_day(today - datetime.timedelta(days=2)), "the day before yesterday", m)
    m = hit(r"last night|yesterday (?:evening|night)|hier soir|gestern (?:abend|nacht)|toi qua|dem qua")
    if m:
        a = _find_day(yesterday)[0]
        return out(a + 17 * 3600, a + 29 * 3600, "last night", m)
    m = hit(r"yesterday|hier|gestern|hom qua")
    if m:
        return out(*_find_day(yesterday), "yesterday", m)
    m = hit(r"this morning|ce matin|heute (?:morgen|fruh|vormittag)|sang nay")
    if m:
        a = _find_day(today)[0]
        return out(a, a + 12 * 3600, "this morning", m)
    m = hit(r"this afternoon|cet apres midi|heute nachmittag|chieu nay")
    if m:
        a = _find_day(today)[0]
        return out(a + 12 * 3600, a + 18 * 3600, "this afternoon", m)
    m = hit(r"tonight|this evening|ce soir|heute abend|toi nay")
    if m:
        a = _find_day(today)[0]
        return out(a + 17 * 3600, a + 24 * 3600, "this evening", m)
    m = hit(r"today|aujourd hui|aujourdhui|heute|hom nay")
    if m:
        return out(*_find_day(today), "today", m)
    m = hit(r"(?:last|past) (\d{1,3}) days|(\d{1,3}) derniers jours|(?:letzten|vergangenen) (\d{1,3}) tagen?|"
            r"(\d{1,3}) ngay qua")
    if m:
        n = int(next(g for g in m.groups() if g))
        return out(now - n * 86400, now, f"the last {n} days", m)
    m = hit(r"(\d{1,3}) days? ago|il y a (\d{1,3}) jours?|vor (\d{1,3}) tagen?|(\d{1,3}) ngay truoc")
    if m:
        n = int(next(g for g in m.groups() if g))
        d = today - datetime.timedelta(days=n)
        return out(*_find_day(d), d.isoformat(), m)
    m = hit(r"last week|past week|previous week|la semaine (?:derniere|passee)|semaine (?:derniere|passee)|"
            r"letzte woche|letzten woche|vorige woche|vorigen woche|vergangene woche|vergangenen woche|tuan truoc")
    if m:
        return out(*_find_day(monday - datetime.timedelta(days=7), 7), "last week", m)
    m = hit(r"this week|cette semaine|diese woche|dieser woche|tuan nay")
    if m:
        return out(*_find_day(monday, 7), "this week", m)
    m = hit(r"last month|past month|previous month|le mois dernier|mois dernier|le mois passe|letzten monat|"
            r"letzter monat|vorigen monat|vergangenen monat|thang truoc")
    if m:
        prev = (first - datetime.timedelta(days=1)).replace(day=1)
        return out(*_find_day(prev, (first - prev).days), "last month", m)
    m = hit(r"this month|ce mois ci|ce mois|diesen monat|diesem monat|thang nay")
    if m:
        return out(*_find_day(first, (today - first).days + 1), "this month", m)
    m = hit(r"recently|lately|recemment|dernierement|kurzlich|neulich|vor kurzem|gan day")
    if m:
        return out(now - 14 * 86400, now, "the last two weeks", m)
    return None, s


def find_secret(value):
    """Whether a text must never be shown (the smart clipboard's rules,
    clipboard_kinds.js secretWhy): a key or a token, a code, a password, a
    card number or a bank account."""
    s = str(value or "").strip()
    if not s:
        return False
    if redact_secrets(s) != s or NOTICE_SECRET.search(s):
        return True
    if re.fullmatch(r"\d{4,8}|\d{3}[ -]\d{3}", s):
        return True
    digits = re.sub(r"[ -]", "", s)
    if re.fullmatch(r"\d{13,19}", digits) and re.fullmatch(r"[\d -]+", s) and luhn(digits):
        return True
    compact = s.replace(" ", "")
    if re.fullmatch(r"[A-Z]{2}\d{2}[A-Z0-9]{11,30}", compact) and sum(c.isdigit() for c in compact) >= 10:
        return True
    if not re.search(r"\s", s) and 8 <= len(s) <= 200 and not re.match(r"(https?://|www\.|(tel|sms|mailto|geo):)", s, re.I) \
            and not re.fullmatch(r"[^@\s]+@[^@\s]+\.[a-zA-Z]{2,}", s):
        lower, upper, digit = re.search(r"[a-z]", s), re.search(r"[A-Z]", s), re.search(r"\d", s)
        symbol = re.search(r"[!@#$%^&*()+=\[\]{};:'\"\\|,<>?~`]", s)
        if (lower and upper and digit) or (symbol and (lower or upper) and digit):
            return True
        if len(s) >= 20 and re.fullmatch(r"[A-Za-z0-9+/_=\-]+", s) and lower and digit:
            return True
        if re.fullmatch(r"[0-9a-fA-F]{32,}", s):
            return True
    return False


def find_url_ok(cfg, url, thorough=True):
    """A link that may be given: a web page, not a site agents may not use
    (browser.blockedSites), carrying no key or code (thorough: every
    secret pattern; the search checks only what it gives that way)."""
    url = str(url or "")
    if not re.match(r"https?://", url, re.I) or FIND_KEYED_URL.search(url) or (thorough and redact_secrets(url) != url):
        return False
    return not any(p.search(url) for p in find_blocked(cfg))


def find_blocked(cfg):
    """browser.blockedSites, compiled once."""
    pats = tuple((cfg.get("browser") or {}).get("blockedSites") or [])
    if _FIND_BLOCKED.get("key") != pats:
        out = []
        for pat in pats:
            with contextlib.suppress(re.error, TypeError):
                out.append(re.compile(pat, re.I))
        _FIND_BLOCKED.update(key=pats, compiled=out)
    return _FIND_BLOCKED["compiled"]


def find_folders():
    """The folders searched for files: Downloads, Documents, Desktop (the
    user's own names, user-dirs.dirs) and the screenshots' folder; only
    those inside the home, never the home itself nor a hidden folder."""
    home = os.path.realpath(os.path.expanduser("~"))
    named = {"DOWNLOAD": "~/Downloads", "DOCUMENTS": "~/Documents", "DESKTOP": "~/Desktop", "PICTURES": "~/Pictures"}
    with contextlib.suppress(OSError):
        with open(os.path.join(xdg("XDG_CONFIG_HOME", "~/.config"), "user-dirs.dirs"), encoding="utf-8") as f:
            for line in f:
                m = re.match(r'\s*XDG_([A-Z]+)_DIR="(.*)"\s*$', line)
                if m and m.group(1) in named:
                    named[m.group(1)] = m.group(2).replace("$HOME", home)
    shots = str(shell_setting("screenSnip.savePath", "~/Pictures/Screenshots")).replace("$HOME", home)
    out = []
    for path in (named["DOWNLOAD"], named["DOCUMENTS"], named["DESKTOP"],
                 os.path.join(named["PICTURES"], "Screenshots"), shots):
        try:
            real = safe_home_path(path)
        except ToolError:
            continue
        if real != home and os.path.isdir(real) and real not in out:
            out.append(real)
    return out


def find_file_text(path, st, ext, deadline):
    """A small text file's or a PDF's text (its first pages), secrets
    blacked out; "" when it can't be read in time."""
    key = (path, st.st_mtime_ns, st.st_size)
    if key in _FIND_TEXT:
        return _FIND_TEXT[key]
    if time.monotonic() > deadline:
        return ""
    out = ""
    if ext == "pdf":
        if st.st_size <= FIND_PDF_MAX and shutil.which("pdftotext"):
            with contextlib.suppress(ToolError):
                proc = run(["pdftotext", "-q", "-l", "3", "-enc", "UTF-8", path, "-"], check=False,
                           timeout=max(0.5, min(2.0, deadline - time.monotonic())))
                out = (proc.stdout or "")[:FIND_READ_BYTES] if proc.returncode == 0 else ""
    else:
        with contextlib.suppress(OSError):
            with open(path, "rb") as f:
                raw = f.read(FIND_READ_BYTES)
            if b"\0" not in raw:
                out = raw.decode("utf-8", errors="replace")
    out = redact_secrets(out)
    if len(_FIND_TEXT) > 400:
        _FIND_TEXT.clear()
    _FIND_TEXT[key] = out
    return out


def find_files(rng, deadline, read=True):
    items = []
    left = FIND_WALK_MAX
    seen = set()
    shown = {}
    for top in find_folders():
        stack = [(top, 0)]
        while stack and left > 0:
            folder, depth = stack.pop()
            try:
                entries = list(os.scandir(folder))
            except OSError:
                continue
            for e in entries:
                if e.name.startswith(".") or e.is_symlink():
                    continue
                try:
                    if e.is_dir():
                        if depth < FIND_WALK_DEPTH and e.name not in FIND_SKIP_DIRS:
                            stack.append((e.path, depth + 1))
                        continue
                    if not e.is_file() or e.path in seen or FIND_SECRET_FILE.search(e.name):
                        continue
                    st = e.stat()
                except OSError:
                    continue
                seen.add(e.path)
                left -= 1
                when = st.st_mtime
                if rng and not rng["from"] <= when < rng["to"]:
                    continue
                ext = e.name.rsplit(".", 1)[1].lower() if "." in e.name[1:] else ""
                if folder not in shown:
                    shown[folder] = home_short(folder)
                items.append({"kind": "file", "title": e.name, "when": when, "where": shown[folder],
                              "path": e.path, "ext": ext, "st": st, "keys": [os.path.basename(folder)],
                              "action": {"open": e.path}})
                if left <= 0:
                    break
    if read:
        readable = [i for i in items if i["ext"] in FIND_TEXT_EXTS or i["ext"] == "pdf"]
        for it in sorted(readable, key=lambda i: -i["when"])[:FIND_READ_MAX]:
            it["text"] = find_file_text(it["path"], it["st"], it["ext"], deadline)
    for it in items:
        del it["st"]
    return items


def zen_places_db():
    """The default Zen profile's places.sqlite, or None."""
    import configparser
    for base in (os.path.join(xdg("XDG_CONFIG_HOME", "~/.config"), "zen"), os.path.expanduser("~/.zen"),
                 os.path.expanduser("~/.var/app/app.zen_browser.zen/.zen")):
        cp = configparser.ConfigParser(interpolation=None)
        try:
            if not cp.read(os.path.join(base, "profiles.ini"), encoding="utf-8"):
                continue
        except (configparser.Error, OSError):
            continue
        paths = [cp[s].get("Default") for s in cp.sections() if s.startswith("Install") and cp[s].get("Default")]
        profiles = [cp[s] for s in cp.sections() if s.startswith("Profile") and cp[s].get("Path")]
        paths += [p["Path"] for p in profiles if p.get("Default") == "1"] + [p["Path"] for p in profiles]
        for p in paths:
            db = p if os.path.isabs(p) else os.path.join(base, p)
            db = os.path.join(db, "places.sqlite")
            if os.path.isfile(db):
                return db
    return None


def zen_places_copy(db):
    """A private copy of places.sqlite (and its write-ahead log: the latest
    visits), Zen keeping its own locked; copied again when Zen wrote since."""
    folder = os.path.join(runtime_dir(), "find-places")
    os.makedirs(folder, mode=0o700, exist_ok=True)
    copy = os.path.join(folder, "places.sqlite")
    stamp = os.path.join(folder, "stamp")
    sources = [db, db + "-wal"]
    now_stamp = json.dumps([[s, os.stat(s).st_mtime_ns, os.stat(s).st_size] for s in sources if os.path.exists(s)])
    with contextlib.suppress(OSError):
        with open(stamp, encoding="utf-8") as f:
            if f.read() == now_stamp and os.path.exists(copy):
                return copy
    for name in os.listdir(folder):
        with contextlib.suppress(OSError):
            os.unlink(os.path.join(folder, name))
    for s in sources:
        if os.path.exists(s):
            shutil.copyfile(s, copy + s[len(db):])
            os.chmod(copy + s[len(db):], 0o600)
    with open(stamp, "w", encoding="utf-8") as f:
        f.write(now_stamp)
    return copy


def find_pages(cfg, rng, want, words_):
    """Zen's history and bookmarks (`want`: a set of "pages", "bookmarks"):
    its places.sqlite read directly (Zen needn't run), else asked through
    nixbook's extension as page_history does."""
    if (cfg.get("browser") or {}).get("history", True) is False:
        return []
    now = time.time()
    since, until = (rng["from"], rng["to"]) if rng else (now - 120 * 86400, now + 60)
    rows = []
    db = zen_places_db()
    if db:
        import sqlite3
        with _FIND_LOCK:
            try:
                con = sqlite3.connect(zen_places_copy(db), timeout=2)
                try:
                    if "pages" in want:
                        rows += [("page", u, t, w / 1e6, n) for u, t, w, n in con.execute(
                            "SELECT p.url, p.title, MAX(v.visit_date) AS last, COUNT(*) FROM moz_historyvisits v "
                            "JOIN moz_places p ON p.id = v.place_id WHERE v.visit_date >= ? AND v.visit_date < ? "
                            "GROUP BY p.id ORDER BY last DESC LIMIT 4000", (int(since * 1e6), int(until * 1e6)))]
                    if "bookmarks" in want:
                        rows += [("bookmark", u, t, (w or 0) / 1e6, 0) for u, t, w in con.execute(
                            "SELECT p.url, b.title, b.dateAdded FROM moz_bookmarks b JOIN moz_places p ON p.id = b.fk "
                            "WHERE b.type = 1 ORDER BY b.dateAdded DESC LIMIT 2000")
                            if not rng or since <= (w or 0) / 1e6 < until]
                finally:
                    con.close()
            except (sqlite3.Error, OSError, ToolError) as e:
                log(f"find: Zen's history: {e}")
                rows = []
    else:
        import types
        for kind in [k for k in ("pages", "bookmarks") if k in want]:
            with contextlib.suppress(ToolError, OSError):
                for it in zen(types.SimpleNamespace(cfg=cfg), "history", kind="history" if kind == "pages" else kind,
                              query=" ".join(words_[:4]), max=50) or []:
                    when = (it.get("when") or 0) / 1000
                    if not rng or since <= when < until:
                        rows.append(("page" if kind == "pages" else "bookmark", it.get("url"), it.get("title"), when,
                                     it.get("visits") or 0))
    items = []
    for kind, url, title, when, visits in rows:
        if not find_url_ok(cfg, url, thorough=False):
            continue
        host = re.sub(r"^www\.", "", re.sub(r"^[a-z]+://([^/?#]*).*", r"\1", url, flags=re.I))
        path = re.sub(r"^[a-z]+://[^/?#]*", "", url, flags=re.I)
        items.append({"kind": kind, "title": short(str(title or url), 150), "when": when or None, "where": host,
                      "url": url, "keys": [host, re.sub(r"[/_\-.?=&#]+", " ", path)], "visits": visits,
                      "check": url, "action": {"open": url}})
    return items


def find_clipboard():
    """The clipboard history (cliphist, newest first), its secrets left out;
    no times: cliphist keeps none."""
    proc = None
    for argv in (["cliphist", "-preview-width", "400", "list"], ["cliphist", "list"]):
        with contextlib.suppress(ToolError):
            proc = run(argv, timeout=3, check=False)
            if proc.returncode == 0:
                break
    if not proc or proc.returncode != 0:
        return []
    items = []
    for line in (proc.stdout or "").splitlines()[:500]:
        cid, _, preview = line.partition("\t")
        preview = preview.strip()
        if not cid.strip().isdigit() or not preview or re.match(r"\[\[ ?binary data", preview) or find_secret(preview):
            continue
        urls = [u for u in FIND_URL.findall(preview)]
        items.append({"kind": "clipboard", "title": short(" ".join(preview.split()), 150), "when": None,
                      "where": "clipboard history", "text": preview,
                      "action": {"copy": preview, "cliphist": cid.strip(), **({"open": urls[0]} if urls else {})}})
    return items


def find_notifications(cfg, rng):
    try:
        with open(notification_history_path(), encoding="utf-8") as f:
            history = json.load(f)
    except (OSError, ValueError):
        return []
    items = []
    for n in reversed(history[-3000:] if isinstance(history, list) else []):
        if not isinstance(n, dict):
            continue
        app = str(n.get("appName") or "")
        summary = str(n.get("summary") or "").translate(BIDI_MARKS)
        body = re.sub(r"<[^>]+>", "", str(n.get("body") or "")).translate(BIDI_MARKS)
        when = n.get("time") / 1000 if isinstance(n.get("time"), (int, float)) else None
        if rng and (when is None or not rng["from"] <= when < rng["to"]):
            continue
        if NOTICE_SECRET_APPS.search(app):
            continue

        def action(body=body):
            urls = [u for u in FIND_URL.findall(body) if find_url_ok(cfg, u)]
            return {"open": urls[0], "copy": urls[0]} if urls else {"copy": body}
        items.append({"kind": "notification", "title": short(summary or app, 150), "when": when, "where": app,
                      "text": body, "keys": [app], "snippet": short(" ".join(body.split()), 200),
                      "check": f"{summary} {body}", "action": action})
    return items


def find_chats(rng):
    path = os.path.join(xdg("XDG_STATE_HOME", "~/.local/state"), "quickshell", "user", "ai", "history", "index.json")
    try:
        with open(path, encoding="utf-8") as f:
            chats = json.load(f).get("chats") or []
    except (OSError, ValueError, AttributeError):
        return []
    items = []
    for c in chats:
        if not isinstance(c, dict) or not c.get("id") or not c.get("title"):
            continue
        t = c.get("updated") or c.get("created")
        when = t / 1000 if isinstance(t, (int, float)) else None
        if rng and (when is None or not rng["from"] <= when < rng["to"]):
            continue
        if find_secret(c["title"]):
            continue
        items.append({"kind": "chat", "title": short(str(c["title"]), 150), "when": when,
                      "where": "conversations with DAI", "chat": c["id"], "action": {"chat": c["id"]}})
    return items


def find_snippet(item, qw):
    """The line of a found file's text that has the words asked."""
    for line in str(item.get("text") or "").splitlines():
        lw = set(words(line))
        if any(_match(q, lw) for q in qw) and not NOTICE_SECRET.search(line):
            return short(" ".join(line.split()), 200)
    return ""


def find_anything(cfg, query, when=None, kinds=None, limit=10, read=True, now=None):
    """The search: {range, results: [{kind, title, when, where, snippet?,
    action}]} (the best first), or a ToolError."""
    query = clean_text(str(query or ""), 300)
    rng, rest = find_when(query, now)
    if when:
        rng, _ = find_when(when, now)
        if not rng:
            raise ToolError("`when`: today, yesterday, Monday, last week, 3 days ago, 2026-10-28… (or leave it out)")
    want = set(kinds or FIND_KINDS)
    qw, hints, exts = [], set(), set()
    for w in words(rest):
        if w in FIND_EXTS:
            exts.update(FIND_EXTS[w])
            hints.add("files")
        elif w in FIND_HINT_OF:
            hints.add(FIND_HINT_OF[w])
        elif w not in FIND_SKIP and w not in qw:
            qw.append(w)
    if hints == {"pages"} and not kinds:
        # "the link Alex sent": links are found in messages too.
        hints.add("notifications")
    deadline = time.monotonic() + FIND_DEADLINE
    items = []
    sources = (("files", lambda: find_files(rng, deadline, read)),
               ("pages", lambda: find_pages(cfg, rng, want & {"pages", "bookmarks"}, qw)),
               ("clipboard", lambda: find_clipboard() if not rng or rng["to"] > time.time() - 7 * 86400 else []),
               ("notifications", lambda: find_notifications(cfg, rng)),
               ("chats", lambda: find_chats(rng)))
    for kind, fetch in sources:
        if kind in want or (kind == "pages" and "bookmarks" in want):
            try:
                items += fetch()
            except Exception as e:  # noqa: BLE001 — one source failing leaves the others
                log(f"find: {kind}: {e!r}")
    plural = {"file": "files", "page": "pages", "bookmark": "bookmarks", "clipboard": "clipboard",
              "notification": "notifications", "chat": "chats"}
    scored = []
    for it in items:
        if exts and (it["kind"] != "file" or it.get("ext") not in exts):
            continue
        hinted = plural[it["kind"]] in hints or (it["kind"] == "bookmark" and "pages" in hints)
        if qw:
            # Folding every word of thousands of pages and messages is most
            # of a search: an ASCII text without even a word's start can't match.
            hay = " ".join([it["title"], *(it.get("keys") or []), it.get("text", "")])
            hay = hay.lower() if hay.isascii() else find_fold(hay)
            if not any(q[:4] in hay for q in qw):
                continue
            score = note_score({"topic": it["title"], "keys": it.get("keys") or [], "text": it.get("text", "")}, qw)
            if not score:
                continue
            score += 2 if hinted else 0
        elif hints and not hinted:
            continue
        else:
            score = 1
        scored.append((score, it.get("when") or 0, it))
    scored.sort(key=lambda x: (-x[0], -x[1]))
    results = []
    for score, _, it in scored:
        if len(results) >= max(1, min(FIND_MAX, limit)):
            break
        # The secret checks, on what would be given only.
        check = it.get("check")
        if check and (NOTICE_SECRET.search(check) or redact_secrets(check) != check):
            continue
        if callable(it["action"]):
            it["action"] = it["action"]()
        out = {k: it[k] for k in ("kind", "title", "where", "path", "url", "chat") if it.get(k)}
        if it.get("when"):
            out["when"] = int(it["when"])
        snippet = it.get("snippet") or (find_snippet(it, qw) if qw and it["kind"] == "file" else "")
        if snippet:
            out["snippet"] = snippet
        out["action"] = it["action"]
        out["score"] = score
        results.append(out)
    return {"range": {k: (int(v) if k != "label" else v) for k, v in rng.items()} if rng else None,
            "words": qw, "results": results}


def find_when_text(t):
    return time.strftime("%a %Y-%m-%d %H:%M", time.localtime(t)) if t else ""


@tool(
    "find_anything",
    "observe",
    "Find something the user saw or kept on this computer, without knowing where: recent files (Downloads, "
    "Documents, Desktop, screenshots: their names and the text of small text files and PDFs), Zen's history "
    "and bookmarks, the clipboard history, past notifications (messages, mails: the links in them), the "
    "past conversations with DAI. For \"that PDF I downloaded Monday\", "
    "\"the link Alex sent about dinner\", \"what did I ask DAI yesterday\". `query`: the user's "
    "words as they said them (time words in it — today, yesterday, Monday, last week, 3 days ago, in English, "
    "French, German or Vietnamese — become a range; `when` gives one apart). `kinds`: only some of files, "
    "pages, bookmarks, clipboard, notifications, chats. Read-only, on this computer, no secrets. "
    "Then: a link, page_go; a file, say its path (the user opens it "
    "from the launcher's find prefix).",
    obj({"query": {"type": "string", "description": "What to find, in the user's words"},
         "when": {"type": "string", "description": "A time apart from the query: today, yesterday, Monday, last week…"},
         "kinds": {"type": "array", "items": {"type": "string", "enum": list(FIND_KINDS)},
                   "description": "Only these kinds (default: all)"},
         "max": {"type": "integer", "description": "At most this many (default 10, at most 30)"}}, ["query"]),
    read_only=True,
    brief=("Find what the user saw or kept: files (PDFs' text too), Zen history/bookmarks, clipboard, "
           "notifications, chats; time words in `query` (Monday, last week…) narrow it."),
    props={"query": None, "when": None, "kinds": {"type": "array", "items": {"type": "string"}}, "max": None},
)
def t_find_anything(ctx, args):
    query = as_str(args, "query", max_len=300)
    when = as_str(args, "when", max_len=100, required=False)
    kinds = args.get("kinds")
    if kinds is not None and (not isinstance(kinds, list) or not kinds or any(k not in FIND_KINDS for k in kinds)):
        raise ToolError("`kinds`: some of " + ", ".join(FIND_KINDS))
    limit = args.get("max", 10)
    if not isinstance(limit, int) or isinstance(limit, bool) or limit < 1:
        raise ToolError("`max` must be a positive integer")
    r = find_anything(ctx.cfg, query, when, kinds, limit)
    rng = r["range"]
    head = f" ({rng['label']}: {find_when_text(rng['from'])} to {find_when_text(rng['to'])})" if rng else ""
    if not r["results"]:
        return [text(f"Nothing found{head}" + (f" for {' '.join(r['words'])}" if r["words"] else "")
                     + ". Try other words, another time, or no time.")]
    lines = [f"Found {len(r['results'])}{head}, the best first:"]
    for i, it in enumerate(r["results"], 1):
        a = it["action"]
        do = (f"open {a['open']}" if a.get("open") else f"conversation {a['chat']} (the side panel's history)" if a.get("chat") else "copy it")
        lines.append(f"{i}. [{it['kind']}] {it['title']} — {it.get('where', '')}"
                     + (f", {find_when_text(it['when'])}" if it.get("when") else "") + f" → {do}")
        if it.get("snippet"):
            lines.append(f"   “{it['snippet']}”")
    return [text("\n".join(lines))]


def find_output(cfg, argv):
    """`find QUERY [--when W] [--kinds a,b] [--max N] [--json]`: the
    launcher's find prefix (the user's own search: no pause), the same
    search as find_anything; nothing with AI off (policies.ai 0). (exit
    code, its output): no print, so the helper runs it on a thread."""
    as_json = "--json" in argv
    argv = [a for a in argv if a != "--json"]
    opts = {"--when": None, "--kinds": None, "--max": "10"}
    rest = []
    i = 0
    while i < len(argv):
        if argv[i] in opts and i + 1 < len(argv):
            opts[argv[i]] = argv[i + 1]
            i += 2
            continue
        rest.append(argv[i])
        i += 1
    if ai_policy() == 0:
        return 0, (json.dumps({"off": True, "results": []}) if as_json else "AI features are off (policies.ai)") + "\n"
    kinds = [k for k in (opts["--kinds"] or "").split(",") if k] or None
    if kinds and any(k not in FIND_KINDS for k in kinds):
        return 2, "--kinds: some of " + ",".join(FIND_KINDS) + "\n"
    try:
        r = find_anything(cfg, " ".join(rest), opts["--when"], kinds, int(opts["--max"]))
    except (ToolError, ValueError) as e:
        return 2, str(e) + "\n"
    if as_json:
        return 0, json.dumps(r, ensure_ascii=False) + "\n"
    return 0, "".join(f"[{it['kind']}] {it['title']} — {it.get('where', '')} {find_when_text(it.get('when'))}".rstrip()
                      + "\n" for it in r["results"])


def find_command(cfg, argv):
    code, out = find_output(cfg, argv)
    (sys.stdout if code == 0 else sys.stderr).write(out)
    return code


# read_document: a whole document's text, for "summarize this file". Claude
# Code's Read stops at 20 MB and its sandbox may have no PDF tools; scanned
# pages (no text layer) are read with OCR.
DOC_TEXT_MAX = 60000        # characters returned in one call, at most
DOC_PAGES_DEFAULT = 30      # pages read when none are asked for
DOC_OCR_PAGES = 10          # pages OCRed in one call, at most
DOC_DEADLINE = 45.0         # seconds for one call (OCR is ~2-5 s a page; calls hold the action lock)
DOC_OCR_DPI = 200
DOC_ZIP_TEXT = {"docx": ("word/document.xml", "</w:p>"), "odt": ("content.xml", "</text:p>"),
                "odp": ("content.xml", "</text:p>"), "ods": ("content.xml", "</text:p>"),
                "pptx": (None, "</a:p>"), "epub": (None, "</p>")}


def doc_pages_arg(value, count):
    """`pages` "3", "2-9", "10-" → (first, last) within 1..count."""
    if value in (None, ""):
        return 1, min(count, DOC_PAGES_DEFAULT)
    m = re.fullmatch(r"\s*(\d+)\s*(?:-\s*(\d*)\s*)?", str(value))
    if not m:
        raise ToolError("`pages` must look like 3, 2-9 or 10-")
    first = int(m.group(1))
    last = first if m.group(2) is None else (int(m.group(2)) if m.group(2) else count)
    if first < 1 or first > count or last < first:
        raise ToolError(f"`pages`: the document has {count} page(s)")
    return first, min(last, count)


def doc_zip_text(path, ext):
    import zipfile
    import html as html_mod
    member, para = DOC_ZIP_TEXT[ext]
    parts = []
    with zipfile.ZipFile(path) as z:
        names = [member] if member else sorted(
            (n for n in z.namelist() if (ext == "pptx" and re.fullmatch(r"ppt/slides/slide\d+\.xml", n))
             or (ext == "epub" and n.lower().endswith((".xhtml", ".html", ".htm")))),
            key=lambda n: [int(t) if t.isdigit() else t for t in re.split(r"(\d+)", n)])
        for n in names:
            xml = z.read(n).decode("utf-8", errors="replace").replace(para, "\n")
            xml = re.sub(r"<(w:tab|text:tab)\b[^>]*/>", "\t", xml)
            parts.append(html_mod.unescape(re.sub(r"<[^>]+>", "", xml)))
            if sum(map(len, parts)) > DOC_TEXT_MAX * 4:
                break
    return "\n".join(parts)


def doc_ocr_page(path, page, lang, timeout):
    png = run(["pdftoppm", "-f", str(page), "-l", str(page), "-r", str(DOC_OCR_DPI), "-gray", "-png", path],
              timeout=max(5, timeout), binary=True).stdout
    return run(["tesseract", "stdin", "stdout", "-l", lang], input=png, timeout=max(5, timeout),
               binary=True).stdout.decode(errors="replace")


@tool(
    "read_document",
    "observe",
    "Read a document's text: PDF (any size; scanned pages are read with OCR), Word (.docx), OpenDocument "
    "(.odt/.odp/.ods), PowerPoint (.pptx), EPUB, or a text file (txt, md, csv, json, html…). Use it rather than "
    "Read or the command line for documents: Read stops at 20 MB and can't read scanned PDFs. `path`: the "
    "file, in the user's home (not a hidden folder). `pages` (PDF): \"3\", \"2-9\", \"10-\" (default the first "
    f"{DOC_PAGES_DEFAULT}); OCR does at most {DOC_OCR_PAGES} scanned pages per call: the reply says which pages "
    "come next. `ocr`: false to skip scanned pages. Read-only; secrets in the text are blacked out.",
    obj({"path": {"type": "string", "description": "The file (absolute, or ~/…)"},
         "pages": {"type": "string", "description": "PDF pages: 3, 2-9 or 10- (default the first 30)"},
         "ocr": {"type": "boolean", "description": "Read scanned pages with OCR (default true)"},
         "max_chars": {"type": "integer", "description": f"At most this much text (default and limit {DOC_TEXT_MAX})"}},
        ["path"]),
    read_only=True,
    brief="A document's text (PDF of any size, scanned too via OCR; docx, odt, pptx, epub, text). Use it, not Read, "
          "for documents.",
    props={"path": None, "pages": "3, 2-9 or 10-", "ocr": None, "max_chars": None},
)
def t_read_document(ctx, args):
    raw = as_str(args, "path", max_len=1024)
    path = safe_home_path(raw[7:] if raw.startswith("file://") else raw)
    name = os.path.basename(path)
    if FIND_SECRET_FILE.search(name):
        raise ToolError(f"refused: {name} looks like a key, a password store or recovery codes")
    if not os.path.isfile(path):
        raise ToolError(f"no such file: {home_short(path)}")
    limit = args.get("max_chars", DOC_TEXT_MAX)
    if not isinstance(limit, int) or isinstance(limit, bool) or limit < 200:
        raise ToolError("`max_chars` must be an integer of at least 200")
    limit = min(limit, DOC_TEXT_MAX)
    ocr = args.get("ocr", True) is not False
    ext = name.rsplit(".", 1)[-1].lower() if "." in name else ""
    head, notes = home_short(path), []
    if ext == "pdf":
        info = run(["pdfinfo", path], timeout=20, check=False)
        if info.returncode != 0:
            raise ToolError(f"{name} isn't a readable PDF" + (" (encrypted?)" if "ncrypt" in (info.stderr or "") else ""))
        m = re.search(r"^Pages:\s+(\d+)", info.stdout or "", re.M)
        count = int(m.group(1)) if m else 1
        first, last = doc_pages_arg(args.get("pages"), count)
        lang = str(ctx.cfg.get("ocrLanguages") or "eng")
        if not re.fullmatch(r"[A-Za-z_]+(\+[A-Za-z_]+)*", lang):
            lang = "eng"
        deadline = time.monotonic() + DOC_DEADLINE
        chunks, ocred, size, stop = [], [], 0, None
        for page in range(first, last + 1):
            left = deadline - time.monotonic()
            if left < 3:
                stop = page
                break
            txt = run(["pdftotext", "-q", "-f", str(page), "-l", str(page), "-layout", "-enc", "UTF-8", path, "-"],
                      timeout=max(3, min(30, left)), check=False).stdout or ""
            if len(re.sub(r"\s", "", txt)) < 25 and ocr:
                if len(ocred) >= DOC_OCR_PAGES:
                    stop = page
                    break
                with contextlib.suppress(ToolError):
                    txt = doc_ocr_page(path, page, lang, min(45, left))
                    ocred.append(page)
            txt = re.sub(r"[ \t]+\n", "\n", re.sub(r"\n{3,}", "\n\n", txt.replace("\f", ""))).strip()
            block = f"--- page {page} ---\n{txt or '(no text)'}\n"
            if size + len(block) > limit and chunks:
                stop = page
                break
            chunks.append(block[:limit - size])
            size += len(chunks[-1])
        done = (stop - 1) if stop else last
        head += f" — PDF, {count} page(s); pages {first}–{done} below"
        if ocred:
            notes.append(f"pages read with OCR ({lang}): " + ", ".join(map(str, ocred)))
        if done < count:
            notes.append(f"more: call again with pages \"{done + 1}-\"")
        body = "".join(chunks)
    elif ext in DOC_ZIP_TEXT:
        try:
            body = doc_zip_text(path, ext)
        except Exception as e:  # not a zip, damaged
            raise ToolError(f"couldn't read {name}: {e}")
    elif ext in FIND_TEXT_EXTS or ext in ("rtf", "tex", "ini", "conf", "toml"):
        with open(path, "rb") as f:
            data = f.read(limit * 4 + 1)
        if b"\0" in data[:4096]:
            raise ToolError(f"{name} isn't text")
        body = data.decode("utf-8", errors="replace")
    else:
        raise ToolError(f"read_document reads PDF, docx, odt/odp/ods, pptx, epub and text files, not .{ext or name}")
    body = redact_secrets(body)
    if ext != "pdf" and len(body) > limit:
        notes.append(f"cut at {limit} characters of {len(body)}")
        body = body[:limit]
    if not body.strip():
        notes.append("no text found" + ("" if ocr or ext != "pdf" else " (ocr: true reads scanned pages)"))
    return [text(head + ("\n" + "; ".join(notes) if notes else "") + "\n\n" + body)]


def helper_find(argv, answer):
    """The launcher's `find` on its own thread (reading files and Zen's
    history can take a second): the shell's quick commands aren't held."""
    try:
        answer(*find_output(load_config(), argv[1:]))
    except Exception as e:  # noqa: BLE001 — a bug in a search must not stop the helper
        log(f"helper: find: {e!r}")
        answer(1, "")


# -- the machine itself --------------------------------------------------------
# Read from /proc and /sys (and lspci for GPU names when it is installed):
# nothing on the desktop, so it answers while desktop control is paused.


def read_sys(path, default=None):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read().strip()
    except OSError:
        return default


def sys_int(path):
    try:
        return int(read_sys(path, ""))
    except ValueError:
        return None


def human_bytes(n):
    if n is None:
        return None
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if n < 1024 or unit == "TiB":
            return f"{n:.1f} {unit}" if unit != "B" else f"{n} B"
        n /= 1024


def human_duration(seconds):
    m, _ = divmod(int(seconds), 60)
    h, m = divmod(m, 60)
    d, h = divmod(h, 24)
    return " ".join(f"{v}{u}" for v, u in ((d, "d"), (h, "h"), (m, "min")) if v) or "under a minute"


def meminfo():
    out = {}
    for line in (read_sys("/proc/meminfo", "") or "").splitlines():
        key, _, value = line.partition(":")
        parts = value.split()
        if parts and parts[0].isdigit():
            out[key] = int(parts[0]) * 1024
    return out


def cpu_times():
    fields = (read_sys("/proc/stat", "") or "").splitlines()[0].split()[1:]
    values = [int(v) for v in fields]
    idle = values[3] + (values[4] if len(values) > 4 else 0)
    return idle, sum(values)


CHASSIS = {3: "desktop", 4: "desktop", 6: "desktop", 7: "tower", 8: "portable", 9: "laptop", 10: "notebook",
           13: "all-in-one", 14: "notebook", 30: "tablet", 31: "convertible", 32: "detachable", 35: "mini PC"}


def machine_info():
    dmi = "/sys/class/dmi/id"
    get = lambda k: (read_sys(f"{dmi}/{k}") or "").strip() or None  # noqa: E731
    junk = {"To Be Filled By O.E.M.", "Default string", "System Product Name", "System manufacturer", "None"}
    clean = lambda v: None if v in junk else v  # noqa: E731
    chassis = sys_int(f"{dmi}/chassis_type")
    out = {
        "vendor": clean(get("sys_vendor")),
        "model": clean(get("product_name")),
        "version": clean(get("product_version")),
        "kind": CHASSIS.get(chassis),
        "motherboard": " ".join(v for v in (clean(get("board_vendor")), clean(get("board_name"))) if v) or None,
        "firmware": {
            "type": "UEFI" if os.path.isdir("/sys/firmware/efi") else "BIOS (legacy)",
            "vendor": get("bios_vendor"),
            "version": get("bios_version"),
            "date": get("bios_date"),
        },
    }
    if clean(get("sys_vendor")) in ("QEMU", "innotek GmbH", "VMware, Inc.", "Microsoft Corporation", "Xen"):
        out["virtual_machine"] = True
    return {k: v for k, v in out.items() if v is not None}
