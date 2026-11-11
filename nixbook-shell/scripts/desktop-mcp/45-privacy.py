# Part of nixbook-desktop-mcp (see ../desktop-mcp.py). The parts run in
# order in one module namespace, as one file: a name defined in any part
# is visible in every other, and tests may replace any function.
#
# The privacy mask: pseudonyms, learning who is private, what was sent, the models.

# Privacy mask
# --------------------------------------------------------------------------

# ai.privacy.mask (on by default): the private details a model would read
# (tool replies, the small model's prompts, the side panel's messages) are
# swapped for placeholders, ⟦Person 2⟧, the same one for a value every time,
# and swapped back here in what a model sends to tools and in its answers.
# Private means known to be: the user's own name and accounts' emails, their
# contacts' names, emails, phones and addresses (nixbook-accounts' copy),
# the terms they add (ai.privacy.terms), and card numbers and IBANs (their
# checksums checked). Public names, sites and addresses stay as they are, so
# answers lose nothing but who the private ones are. Plain code, no model:
# one compiled regex, well under a millisecond a reply. ai.privacy.screenshots
# (off by default: about a second of OCR a full screenshot) boxes them in
# screenshots too. The table is privacy-map.json, 0600, never sent.
PRIVACY_TOKEN = re.compile(r"⟦([A-Z][A-Za-z]*)(?: (\d+))?(?: (first|nick|login))?⟧")
# Login names that are words, defaults or service accounts, not someone's:
# never masked. CI's (GitHub Actions' runner: its paths, /home/runner/…, are
# in every test's replies).
PRIVACY_GENERIC_LOGINS = set("root user admin administrator debian ubuntu nixos fedora arch guest pi test demo dev "
                             "home live default owner runner builder jenkins gitlab-runner".split())
PRIVACY_MIN = 3
# A given name that is also a common word ("May I…"): masked with the full
# name only.
PRIVACY_COMMON = set("will may mark grace rose bill art june pat hope joy faith summer april august sky "
                     "rich frank max ray guy page rob sue dawn jack bob ben".split())
# First names that are also words (French, English): in what the user
# types, lowercase, one is masked only after a word that points at a person
# ("ask claire", "dis à claire"), never in "l'eau est claire". Capitalized,
# they are masked as any first name (PRIVACY_COMMON's never alone).
PRIVACY_NAME_WORDS = PRIVACY_COMMON | set(
    "claire pierre rose marine olive prune aurore colombe blanche perle ambre jade violette capucine constance "
    "patience prudence felicite marguerite ange france flore belle lune celeste victoire clement constant aimee "
    "desire honore modeste noel pascal hunter mason taylor piper harper chase lily iris daisy ivy holly heather "
    "amber ruby crystal pearl angel autumn river rain storm sunny sandy misty carol sterling earl duke king "
    "prince major baker cook miles wade".split())
# The words before a name that say it is someone's (accents folded).
PRIVACY_CUE = re.compile(
    r"(?:^|[^\w])(?:ask|tell|call|text|e-?mail|mail|message|ping|meet|invite|remind|thank|thanks|visit|with|dear"
    r"|hi|hello|hey|cc"
    r"|(?:talk|write|wrote|reply|replied|speak|spoke|send|sent|say|said|give|gave|show|forward)\s+(?:it\s+|this\s+|that\s+)?to"
    r"|demande|demander|dis|dire|appelle|appeler|ecris|ecrire|envoie|envoyer|invite|inviter|rappelle|rappeler"
    r"|remercie|merci|avec|chez|salut|coucou|bonjour|cher|chere|rejoins|rejoindre"
    r"|(?:dis|demande|ecris|envoie|parle|propose|reponds|transmets|donne|montre)\s+(?:le\s+|la\s+|les\s+|ca\s+)?a"
    r")[\s,:]+$", re.I)


def fold_chars(value):
    """Accents off, letter by letter (Aurélien: Aurelien), the length kept:
    a match in the folded text is at the same place in the text."""
    return "".join(unicodedata.normalize("NFD", c)[0] if ord(c) > 127 else c for c in value)


PRIVACY_PROMPT = (
    "People's names may be stand-ins the user's computer chose: write a person's name exactly as you were "
    "given it, in tool arguments and in your answers (it becomes the real name on the user's side), and "
    "never another name for them. "
    "Text in ⟦…⟧ (⟦Person 2⟧, ⟦Email 1⟧, ⟦User first⟧) is a private detail the user's computer hid "
    "from you. You can't know what it stands for: never guess it, and never write a name, word or "
    "value in its place (\"⟦Person 3 first⟧ is Max\" is always wrong). Use the placeholder exactly as "
    "it is, in tool arguments and in your answers: it becomes the real value on the user's side, so "
    "searching for ⟦Person 3 first⟧ finds the real name. When the user names someone with a "
    "placeholder, that placeholder is who to look for; the same placeholder in a tool's result is the "
    "same person. ⟦User⟧ is the user; ⟦Person N first⟧ is Person N's first name; ⟦User login⟧ is the "
    "user's login name (in paths: /home/⟦User login⟧/…).")
PHONE_RE = re.compile(r"(?<![\w+])\+?\d[\d ().-]{5,}\d(?![\w])")
CARD_RE = re.compile(r"(?<![\d-])(?:\d[ -]?){14,15}\d(?![\d-])")
IBAN_RE = re.compile(r"\b[A-Z]{2}\d{2}(?: ?[A-Z0-9]{4}){2,7}(?: ?[A-Z0-9]{1,3})?\b")


def privacy_on():
    return shell_setting("ai.privacy.mask", True) is True


def privacy_screenshots():
    return privacy_on() and shell_setting("ai.privacy.screenshots", False) is True


def privacy_map_path():
    return os.path.join(xdg("XDG_STATE_HOME", "~/.local/state"), "nixbook-shell", "privacy-map.json")


# Pseudonyms (ai.privacy.pseudonyms, on by default): a hidden person is shown
# to the model as a stable fake name (Alan AMOYEL → "Brisa Ashdown") rather
# than ⟦Person 7⟧. Given a placeholder, models wrote a name of their own in
# its place ("Looking for Julie…" for ⟦Person 7 first⟧); given a name they
# keep it, and every word of it comes back to the real one for the user and
# the tools (unmask_text). Rare names, never one of the user's contacts'
# (privacy_pseudo_free), so a real person in the data is hardly ever one.
# Logins and nicknames stay placeholders (paths, handles: exact values).
PSEUDO_FIRST = (
    "Aurelio Brisa Caspian Daria Elio Fenna Gideon Halia Idris Junia Kasimir Leandra Malo Nerea Orrin Paloma "
    "Quillan Sylas Tamsin Ulric Vesna Wendel Xiomara Ysolde Zoran Anouk Bodhi Dashiell Emeric Florin Galen "
    "Henrike Isolde Jorund Kaia Lisandro Niamh Odalys Perrin Rasmus Saoirse Thaddeus Ulla Vidar Willa Zinnia "
    "Ambrose Briony Corentin Desma Evander Fiora Hollis Ines Joachim Kerensa Lazlo Marisol Nikolai Ottilie").split()
PSEUDO_LAST = (
    "Ashdown Brennig Calloway Dunmore Everhart Falkner Halloran Ivers Jessop Kincaid Lorimer Merriman Northcott "
    "Oakhurst Pendry Quarles Rennick Stroud Talbott Upworth Vandermeer Whitlock Yardley Zellner Ainsworth "
    "Blackwood Corriveau Esterby Fairbanks Galloway Hargreave Ironside Kettering Lindqvist Marchetti Norwood "
    "Ostrander Prescott Radcliffe Thornbury Underhill Wexford Abernethy Bramwell Castellane Delacourt "
    "Fennimore Grantham Holloway Ingleby Jardine Kilbride Larchmont Mortimer Neville Oldcastle").split()


def privacy_pseudonyms():
    """Whether hidden people are shown to the model as fake names (else as
    ⟦Person N⟧). NIXBOOK_PRIVACY_PSEUDONYMS=0/1 overrides (tests)."""
    env = os.environ.get("NIXBOOK_PRIVACY_PSEUDONYMS")
    if env in ("0", "1"):
        return env == "1"
    return shell_setting("ai.privacy.pseudonyms", True) is not False


_PSEUDO = {"key": None, "words": frozenset(), "re": None, "map": {}}


def privacy_pseudo(tokens=None):
    """The pseudonyms given so far: {"words": folded words, "re": a regex of
    them (whole words, longest first, any case), "map": {lower: real}}.
    Kept while privacy-map.json stays the same."""
    if tokens is None:
        try:
            st = os.stat(privacy_map_path())
            key = (st.st_mtime_ns, st.st_size)
        except OSError:
            key = None
        if key is not None and _PSEUDO["key"] == key:
            return _PSEUDO
        tokens = privacy_tokens()
    else:
        key = ("given", id(tokens), len(tokens))
        if _PSEUDO["key"] == key:
            return _PSEUDO
    names = {k: v for k, v in tokens.items() if k and not k.startswith("⟦") and isinstance(v, str)}
    alts = sorted(names, key=len, reverse=True)
    _PSEUDO.update(key=key, map={k.lower(): v for k, v in names.items()},
                   words=frozenset(fold(w) for k in names for w in k.split()),
                   # A mention (@Brisa) too, never an email's domain (x@brisa.com).
                   re=re.compile(r"(?:(?<![\w@.])|(?<=@)(?<![\w.]@))(" + "|".join(re.escape(a) for a in alts)
                                 + r")(?![\w@])", re.I)
                   if alts else None)
    return _PSEUDO


def privacy_pseudo_free(taken, pool, vocab_words):
    """The first name of POOL neither given nor anyone's in the user's data."""
    for name in pool:
        if fold(name) not in taken and fold(name) not in vocab_words:
            return name
    return None


def privacy_files():
    state = os.path.join(xdg("XDG_STATE_HOME", "~/.local/state"), "nixbook-accounts")
    return [os.path.join(xdg("XDG_CONFIG_HOME", "~/.config"), "nixbook-shell", "config.json"),
            os.path.join(state, "contacts.json"), os.path.join(state, "accounts.json"), privacy_learned_path()]


def privacy_learned_path():
    return os.path.join(xdg("XDG_STATE_HOME", "~/.local/state"), "nixbook-shell", "privacy-learned.json")


def privacy_seen_path():
    return os.path.join(xdg("XDG_STATE_HOME", "~/.local/state"), "nixbook-shell", "privacy-seen.json")


def read_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def contacts_in(node, out):
    """Every contact-shaped object in nixbook-accounts' copy, however it is
    nested (accounts' sections)."""
    if isinstance(node, dict):
        if isinstance(node.get("name"), str) and ("emails" in node or "phones" in node or "givenName" in node):
            out.append(node)
        else:
            for v in node.values():
                contacts_in(v, out)
    elif isinstance(node, list):
        for v in node:
            contacts_in(v, out)
    return out


def emails_in(node, out):
    """The accounts' emails (an account's name may be one)."""
    if isinstance(node, dict):
        for k, v in node.items():
            if isinstance(v, str) and k in ("email", "name") and "@" in v:
                out.append(v)
            else:
                emails_in(v, out)
    elif isinstance(node, list):
        for v in node:
            emails_in(v, out)
    return out


def privacy_people():
    """([(person id, full name, given, family, nickname, emails, phones,
    addresses)]: the user first, the user's terms, the contacts' Discord
    names from their notes)."""
    import pwd
    try:
        gecos = pwd.getpwuid(os.getuid()).pw_gecos.split(",")[0].strip()
    except KeyError:
        gecos = ""
    config, contacts, accounts = (read_json(p) for p in privacy_files()[:3])
    shown = ((config or {}).get("profile") or {}).get("displayName") or ""
    mails = list(dict.fromkeys(emails_in(accounts, [])))
    people, handles = [], []
    for full in dict.fromkeys(n for n in (gecos, shown) if n):
        parts = full.split()
        people.append(("user", full, parts[0] if len(parts) > 1 else "", parts[-1] if len(parts) > 1 else "",
                       "", mails, [], []))
    if not people and mails:
        people.append(("user", "", "", "", "", mails, [], []))
    for c in contacts_in(contacts, []):
        vals = lambda k: [t.get("value") for t in c.get(k) or [] if isinstance(t, dict) and isinstance(t.get("value"), str)]
        people.append((str(c.get("id") or fold(c["name"])), c["name"], c.get("givenName") or "",
                       c.get("familyName") or "", c.get("nickname") or "", vals("emails"), vals("phones"),
                       [*vals("addresses"), *(a.get("street") for a in c.get("addresses") or []
                                              if isinstance(a, dict) and isinstance(a.get("street"), str))]))
        # The Discord name a note gives ("Discord: alesio"): the discord
        # tool finds people by it and prints it, as Discord does.
        handles.extend(note_discord_names(c.get("notes")))
    # Learned: "Alice Durand" a person, "Alice" alone her first name (case
    # kept: never "alice").
    learned = (read_json(privacy_learned_path()) or {}).get("learned") or {}
    for key, e in learned.items() if isinstance(learned, dict) else []:
        value = str(e.get("value") or "") if isinstance(e, dict) else ""
        if e.get("kind") == "Email":
            people.append((f"learned:{key}", "", "", "", "", [value], [], []))
        elif len(value.split()) > 1:
            people.append((f"learned:{key}", value, value.split()[0], "", "", [], [], []))
        elif value:
            people.append((f"learned:{key}", "", value, "", "", [], [], []))
    terms = (config or {}).get("ai", {}).get("privacy", {}).get("terms") if isinstance(config, dict) else None
    return people, [t for t in terms or [] if isinstance(t, str)], handles


def trie_regex(values):
    """One regex for many values, their common prefixes factored: fast on
    thousands of contacts. A space matches any run of spaces."""
    trie = {}
    for v in values:
        node = trie
        for ch in v:
            node = node.setdefault(ch, {})
        node[""] = {}

    def walk(node):
        alts = [(r"\s+" if ch == " " else re.escape(ch)) + walk(sub) for ch, sub in sorted(node.items()) if ch]
        if not alts:
            return ""
        body = alts[0] if len(alts) == 1 else "(?:" + "|".join(alts) + ")"
        return f"(?:{body})?" if "" in node else body
    return walk(trie)


_PRIVACY = {"key": None}


def privacy_vocab():
    """{"ci": regex, "cs": regex, "keys": {normalized value: (kind, person,
    part, value)}, "phones": {last 9 digits: phone}}, built again when the
    contacts, accounts or settings change."""
    key = tuple(os.path.getmtime(p) if os.path.exists(p) else 0 for p in privacy_files())
    if _PRIVACY["key"] == key:
        return _PRIVACY
    people, terms, handles = privacy_people()
    # Keys accents off (fold_chars), as the text is matched: Aurelien,
    # Aurélien and AURÉLIEN are one name.
    ci, cs, loose, phones = {}, {}, {}, {}
    norm = lambda s: fold_chars(" ".join(s.split()))
    given = {}
    for pid, full, first, last, nick, *_ in people:
        for part in (first, nick):
            if part:
                given.setdefault(norm(part).lower(), set()).add(pid)
    for pid, full, first, last, nick, emails, numbers, addresses in people:
        if len(full) >= PRIVACY_MIN:
            ci.setdefault(norm(full).lower(), ("Person", pid, None, " ".join(full.split())))
        # Not a family name alone: rarely who someone is, often a public
        # name too (Martin Luther King).
        for part, name in (("first", first), ("nick", nick)):
            key = norm(name)
            if len(name) < PRIVACY_MIN or key.lower() in loose:
                continue
            # A name several people share: a name of its own, nobody's in particular.
            shared = len(given.get(key.lower(), ())) > 1
            spec = ("Name", name, None, name) if shared else ("Person", pid, part, name, " ".join(full.split()))
            # In what the user types: any case (loose).
            loose[key.lower()] = spec
            if key.lower() in PRIVACY_COMMON:
                continue
            # Elsewhere: as written (Claire, never the word claire), or in
            # capitals.
            cs[key] = spec
            cs[key.upper()] = spec
        for e in emails:
            if "@" in e:
                ci.setdefault(norm(e).lower(), ("Email", e.strip().lower(), None, e.strip()))
        for p in numbers:
            digits = re.sub(r"\D", "", p)
            if len(digits) >= 7:
                phones[digits[-9:]] = p.strip()
        for a in addresses:
            if len(a) >= 8:
                ci.setdefault(norm(a).lower(), ("Address", " ".join(a.lower().split()), None, " ".join(a.split())))
    for t in terms:
        t = " ".join(t.split())
        if len(t) >= PRIVACY_MIN:
            ci.setdefault(norm(t).lower(), ("Private", t.lower(), None, t))
    # Discord names in any case (Discord shows them in lower case), but not
    # one that is a common first name or word alone (the person's own name
    # is already masked as one).
    # A mention too (@alesio): its own regex, an @ before it allowed.
    handle = {}
    for h in handles:
        if len(h) >= PRIVACY_MIN and h.lower() not in PRIVACY_NAME_WORDS and norm(h).lower() not in ci:
            handle.setdefault(norm(h).lower(), ("Handle", h.lower(), None, h))
    # The login name: in paths (/home/NAME/…) and prompts, case kept.
    import pwd
    try:
        login = pwd.getpwuid(os.getuid()).pw_name
    except KeyError:
        login = ""
    if len(login) >= PRIVACY_MIN and login.lower() not in PRIVACY_GENERIC_LOGINS and login not in cs:
        cs[login] = ("Person", "user", "login", login)
    bound = lambda body: re.compile(rf"(?<![\w@.]){body}(?![\w@])" if body else r"(?!)")
    learn = read_json(privacy_learned_path()) or {}
    config = read_json(privacy_files()[0]) or {}
    settings = (config.get("ai") or {}).get("privacy") or {} if isinstance(config, dict) else {}
    after = settings.get("learnAfter", PRIVACY_LEARN_AFTER)
    _PRIVACY.update(learn=settings.get("learn", True) is True,
                    after=after if isinstance(after, int) and not isinstance(after, bool) and after >= 1 else PRIVACY_LEARN_AFTER,
                    ignored=set(learn.get("ignored") or []) if isinstance(learn, dict) else set())
    _PRIVACY.update(key=key, ci=re.compile(bound(trie_regex(ci)).pattern, re.I), cs=bound(trie_regex(cs)),
                    loose=re.compile(bound(trie_regex(loose)).pattern, re.I),
                    handle=re.compile(rf"(?<![\w.]){trie_regex(handle)}(?![\w@])" if handle else r"(?!)", re.I),
                    keys={**{("ci", k): v for k, v in ci.items()}, **{("cs", k): v for k, v in cs.items()},
                          **{("loose", k): v for k, v in loose.items()}, **{("handle", k): v for k, v in handle.items()}},
                    phones=phones)
    return _PRIVACY


def luhn(digits):
    total = 0
    for i, d in enumerate(reversed(digits)):
        d = int(d) * (2 if i % 2 else 1)
        total += d - 9 if d > 9 else d
    return total % 10 == 0


def iban_ok(value):
    s = value.replace(" ", "")
    s = s[4:] + s[:4]
    try:
        return 15 <= len(s) <= 34 and int("".join(str(int(c, 36)) for c in s)) % 97 == 1
    except ValueError:
        return False


def privacy_spans(value, vocab, typed=False):
    """[(start, end, (kind, id, part, real value))], not overlapping. typed:
    what the user typed (the side panel), where a first name is lowercase
    too: masked, unless it is also a word (claire) and no word before it
    points at a person (PRIVACY_CUE)."""
    spans = []
    folded = fold_chars(value)
    for case in ("ci", "cs", "handle", "loose") if typed else ("ci", "cs", "handle"):
        for m in vocab[case].finditer(folded):
            norm = " ".join(m.group().split())
            spec = vocab["keys"].get((case, norm if case == "cs" else norm.lower()))
            if not spec:
                continue
            if case == "loose" and norm.lower() in PRIVACY_NAME_WORDS and not (
                    norm[:1].isupper() and norm.lower() not in PRIVACY_COMMON) and not PRIVACY_CUE.search(folded[:m.start()]):
                continue
            spans.append((m.start(), m.end(), spec))
    if vocab["phones"]:
        for m in PHONE_RE.finditer(value):
            digits = re.sub(r"\D", "", m.group())
            if len(digits) >= 7 and digits[-9:] in vocab["phones"]:
                spans.append((m.start(), m.end(), ("Phone", digits[-9:], None, vocab["phones"][digits[-9:]])))
    for m in CARD_RE.finditer(value):
        digits = re.sub(r"\D", "", m.group())
        if re.match(r"4|5[1-5]|2[2-7]|3[47]|6", digits) and luhn(digits):
            spans.append((m.start(), m.end(), ("Card", digits, None, m.group())))
    for m in IBAN_RE.finditer(value):
        if iban_ok(m.group()):
            spans.append((m.start(), m.end(), ("IBAN", m.group().replace(" ", ""), None, m.group())))
    spans.sort(key=lambda s: (s[0], -s[1]))
    out, end = [], -1
    for s in spans:
        if s[0] >= end:
            out.append(s)
            end = s[1]
    return out


class LockedJson:
    """A JSON object in a 0600 file, read and written under an exclusive
    lock (several servers and the shell at once); written back if changed."""
    keys = ()

    def path(self):
        raise NotImplementedError

    def __enter__(self):
        path = self.path()
        os.makedirs(os.path.dirname(path), exist_ok=True)
        self.lockfd = os.open(path + ".lock", os.O_WRONLY | os.O_CREAT, 0o600)
        fcntl.flock(self.lockfd, fcntl.LOCK_EX)
        data = read_json(path)
        self.data = data if isinstance(data, dict) else {}
        for k in self.keys:
            self.data.setdefault(k, {})
        self.changed = False
        return self

    def __exit__(self, *exc):
        try:
            if self.changed:
                path = self.path()
                fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".privacy.")
                with os.fdopen(fd, "w", encoding="utf-8") as f:
                    json.dump(self.data, f, ensure_ascii=False)
                os.replace(tmp, path)
        finally:
            os.close(self.lockfd)


# Learning who else is private (ai.privacy.learn, on by default): a name a
# model would read where only a person's name goes (a mail's From:/To:,
# "Name <email>", a chat app's notification sender, "Hi Name,") and a
# personal email address (not support@, noreply@…) are counted, once per
# distinct line (the same notification read again counts once). Seen in
# ai.privacy.learnAfter (3) lines, it is private from then on, like a
# contact; until then it is sent as it is. Plain regexes on the text masked
# anyway, a few microseconds; a file written only when something is found.
# The counts (privacy-seen.json: a stranger unseen for 60 days is
# forgotten) and the names learned (privacy-learned.json, with those the
# user said aren't private: "ignored") stay here, 0600.
PRIVACY_LEARN_AFTER = 3
PRIVACY_SEEN_DAYS = 60
PRIVACY_SEEN_MAX = 2000
PRIVACY_NAME = r"(?<![\w'’-])([^\W\d_][\w'’-]*(?: [^\W\d_][\w'’-]*){0,2})"
PRIVACY_EMAIL = r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+"
PRIVACY_CUES = [
    re.compile(r'"?' + PRIVACY_NAME + r'"? <(' + PRIVACY_EMAIL + r")>"),
    re.compile(r"(?im)^[ \t]*(?:from|to|cc|de|à|von|an)[ \t]*:[ \t]*\"?" + PRIVACY_NAME + r"\"?[ \t]*(?:<|,|$)"),
    re.compile(r"\[(?i:signal|whatsapp|telegram|discord|vesktop|slack|element|fractal|messenger|teams|kdeconnect|"
               r"messages|sms|beeper|session|threema|wire)[^\]]{0,40}\] " + PRIVACY_NAME + r":"),
    re.compile(r"(?im)^[ \t]*(?:hi|hello|hey|dear|bonjour|salut|coucou|hallo|hola|ciao)[ \t]+" + PRIVACY_NAME + r"[ \t]*[,!]"),
]
PRIVACY_EMAIL_RE = re.compile(r"(?<![\w.+-])" + PRIVACY_EMAIL)
PRIVACY_ROLE = re.compile(
    r"^(no-?reply|do-?not-?reply|notifications?|notify|support|info|contact|hello|hi|team|news(letter)?|admin|"
    r"billing|sales|security|service|help|mailer-daemon|postmaster|updates?|alerts?|bot|jobs|careers|press|"
    r"privacy|marketing|feedback|invoice|receipts?|orders?|account|accounts|bounces?|webmaster|root|example)\b", re.I)
PRIVACY_NOT_NAMES = set(
    "team support notifications notification noreply github gitlab google amazon apple microsoft facebook meta "
    "linkedin twitter slack discord inc ltd llc sas gmbh sa app bot service admin newsletter news info security "
    "account update updates store shop bank the your you all everyone there world folks guys group channel "
    "general bonjour me us them unknown sender customer client user friend friends family mom mum dad".split())


def looks_like_name(name):
    """Looks like someone's name: one to three capitalized words, no
    acronym, no word that says it's a company or a role."""
    words_ = name.split()
    return (len(name) >= PRIVACY_MIN and 1 <= len(words_) <= 3
            and all(w[0].isupper() and not (len(w) > 1 and w.isupper()) for w in words_)
            and not any(fold(w) in PRIVACY_NOT_NAMES for w in words_)
            and not (len(words_) == 1 and fold(name) in PRIVACY_COMMON))


def privacy_vocab_words():
    """The folded words of every name the mask knows (contacts, learned
    ones, the user's): never given as a pseudonym."""
    vocab = privacy_vocab()
    out = set()
    for spec in vocab["keys"].values():
        for v in spec[3:5]:
            if isinstance(v, str):
                out.update(fold(w) for w in v.split())
    return out


def privacy_known(value, vocab):
    """Already private (or a placeholder, or a pseudonym given: never learned
    as a stranger of its own)."""
    if "⟦" in value:
        return True
    if any(fold(w) in privacy_pseudo()["words"] for w in value.split()):
        return True
    norm = fold_chars(" ".join(value.split()))
    return bool(vocab["ci"].fullmatch(norm) or vocab["cs"].fullmatch(norm) or vocab["handle"].fullmatch(norm))


def privacy_candidates(value, vocab):
    """{(kind, value): the line it was seen on} in a text."""
    found = {}

    def line_at(i):
        end = value.find("\n", i)
        return value[value.rfind("\n", 0, i) + 1:end if end >= 0 else len(value)]
    for cue in PRIVACY_CUES:
        for m in cue.finditer(value):
            # The capitalized words just before the cue ("Message from
            # Alice Martin <…>": Alice Martin).
            words_ = m.group(1).split()
            while words_ and not words_[0][0].isupper():
                words_.pop(0)
            name = " ".join(words_)
            if looks_like_name(name) and not privacy_known(name, vocab):
                found.setdefault(("Person", name), line_at(m.start()))
    for m in PRIVACY_EMAIL_RE.finditer(value):
        email = m.group().lower().rstrip(".")
        if not PRIVACY_ROLE.match(email.split("@")[0]) and not privacy_known(email, vocab):
            found.setdefault(("Email", email), line_at(m.start()))
    return {k: v for k, v in found.items() if f"{k[0]}:{fold(k[1])}" not in vocab["ignored"]}


class PrivacySeen(LockedJson):
    keys = ("seen",)
    path = staticmethod(privacy_seen_path)


class PrivacyLearned(LockedJson):
    keys = ("learned",)
    path = staticmethod(privacy_learned_path)


def privacy_learn(value, vocab):
    """Counts the strangers a text names; True when one became private."""
    found = privacy_candidates(value, vocab)
    if not found:
        return False
    now = int(time.time())
    promoted = []
    with PrivacySeen() as s:
        seen = s.data["seen"]
        for (kind, name), line in found.items():
            key = f"{kind}:{fold(name)}"
            e = seen.setdefault(key, {"kind": kind, "value": name, "lines": []})
            h = hashlib.sha256(" ".join(line.split()).encode()).hexdigest()[:12]
            if h in e["lines"]:
                continue
            e["lines"] = (e["lines"] + [h])[-10:]
            e["n"], e["last"] = e.get("n", 0) + 1, now
            s.changed = True
            if e["n"] >= vocab["after"]:
                promoted.append((key, seen.pop(key)))
        if s.changed:
            since = now - PRIVACY_SEEN_DAYS * 86400
            kept = sorted(((k, e) for k, e in seen.items() if e.get("last", 0) >= since), key=lambda x: -x[1].get("last", 0))
            s.data["seen"] = dict(kept[:PRIVACY_SEEN_MAX])
    if not promoted:
        return False
    with PrivacyLearned() as m:
        for key, e in promoted:
            m.data["learned"][key] = {"kind": e["kind"], "value": e["value"], "since": now, "seen": e["n"]}
        m.changed = True
    return True


def privacy_unlearn(key):
    """Not private after all: forgotten, and never learned again."""
    with PrivacyLearned() as m:
        e = m.data["learned"].pop(key, None)
        ignored = m.data.get("ignored") or []
        if key not in ignored:
            m.data["ignored"] = ignored + [key]
        m.changed = True
    with PrivacySeen() as s:
        s.changed = s.data["seen"].pop(key, None) is not None
    return e is not None


class PrivacyMap(LockedJson):
    """The table of placeholders: kept between sessions so a value keeps
    its placeholder."""
    keys = ("tokens", "keys", "next", "people", "pseudo")
    path = staticmethod(privacy_map_path)

    def pseudonym(self, ident, first, full):
        """A person's fake name for the model: its first name (and a last
        one when the real name has one), the same each time; its words
        mapped back to the real ones (tokens). None when the pools are spent."""
        p = self.data["pseudo"].get(ident)
        if not p:
            taken = {fold(w) for q in self.data["pseudo"].values() for w in (q.get("first"), q.get("last")) if w}
            vocab_words = privacy_vocab_words()
            p = {"first": privacy_pseudo_free(taken, PSEUDO_FIRST, vocab_words)}
            if not p["first"]:
                return None
            p["last"] = privacy_pseudo_free(taken, PSEUDO_LAST, vocab_words)
            self.data["pseudo"][ident] = p
            self.changed = True
        words = (full or first or "").split()
        real_first = first or (words[0] if words else "")
        real_last = " ".join(w for w in words if fold(w) != fold(real_first)) if len(words) > 1 else ""
        pairs = [(p["first"], real_first)]
        if p.get("last") and real_last:
            pairs += [(p["last"], real_last), (f"{p['first']} {p['last']}", " ".join(words))]
        for k, v in pairs:
            if v and self.data["tokens"].get(k) != v:
                self.data["tokens"][k] = v
                self.changed = True
        return p

    def token(self, spec):
        """spec: (kind, id, part, real value[, the person's full name])."""
        kind, ident, part, real = spec[:4]
        if privacy_pseudonyms() and kind in ("Person", "Name") and part in (None, "first"):
            # A fake name rather than a placeholder (PSEUDO_FIRST).
            full = spec[4] if len(spec) > 4 and spec[4] else (real if part is None else "")
            p = self.pseudonym(f"{kind}:{ident}", real if part == "first" or kind == "Name" else "", full)
            if p:
                if part == "first" or kind == "Name" or not (p.get("last") and len(full.split()) > 1):
                    return p["first"]
                return f"{p['first']} {p['last']}"
        if kind == "Person":
            if ident == "user":
                base = "User"
            else:
                n = self.data["people"].get(ident)
                if n is None:
                    n = self.data["people"][ident] = self.data["next"].get("Person", 0) + 1
                    self.data["next"]["Person"] = n
                    self.changed = True
                base = f"Person {n}"
            tok = f"⟦{base}{' ' + part if part else ''}⟧"
            # The first name told: the full name may come back too.
            for t, v in ((tok, real), *([(f"⟦{base}⟧", spec[4])] if part and len(spec) > 4 and spec[4] else [])):
                if self.data["tokens"].get(t) != v:
                    self.data["tokens"][t] = v
                    self.changed = True
            return tok
        key = f"{kind}:{ident}"
        tok = self.data["keys"].get(key)
        if not tok:
            n = self.data["next"][kind] = self.data["next"].get(kind, 0) + 1
            tok = self.data["keys"][key] = f"⟦{kind} {n}⟧"
            self.data["tokens"][tok] = real
            self.changed = True
        return tok


def mask_text(value, vocab=None, typed=False, learn=True, pmap=None):
    """`learn` False: masked without counting the strangers it names (text
    already counted when it was masked to be sent, e.g. the sent log's copy:
    counted twice, a name became private after two sightings, not three)."""
    if not value:
        return value
    if vocab is None:
        if not privacy_on():
            return value
        vocab = privacy_vocab()
    if learn and vocab["learn"] and privacy_learn(value, vocab):
        vocab = privacy_vocab()
    spans = privacy_spans(value, vocab, typed)
    if not spans:
        return value
    if pmap is None:
        with PrivacyMap() as m:
            return _with_tokens(value, spans, m)
    return _with_tokens(value, spans, pmap)


def _with_tokens(value, spans, m):
    out, at = [], 0
    for start, end, spec in spans:
        out += [value[at:start], m.token(spec)]
        at = end
    return "".join(out) + value[at:]


def privacy_tokens():
    data = read_json(privacy_map_path())
    return (data or {}).get("tokens") or {} if isinstance(data, dict) else {}


def unmask_text(value, tokens=None):
    """The real values back: ⟦…⟧ placeholders, and the pseudonyms given
    (whole words, any case: "Brisa", "Brisa Ashdown", "Ashdown")."""
    if not value:
        return value
    pseudo = privacy_pseudo(tokens)
    if "⟦" not in value and not pseudo["re"]:
        return value
    tokens = privacy_tokens() if tokens is None else tokens
    if "⟦" in value:
        value = PRIVACY_TOKEN.sub(lambda m: tokens.get(m.group(), m.group()), value)
    if pseudo["re"]:
        value = pseudo["re"].sub(lambda m: pseudo["map"].get(m.group().lower(), m.group()), value)
    return value


def mask_obj(obj, vocab=None, pmap=None):
    """Every string in a JSON value masked (an image's data left as it is):
    the placeholder table opened once for the whole value, not per string."""
    if vocab is None:
        if not privacy_on():
            return obj
        vocab = privacy_vocab()
    if isinstance(obj, str):
        return mask_text(obj, vocab, pmap=pmap)
    if pmap is None and isinstance(obj, (list, dict)):
        with PrivacyMap() as m:
            return mask_obj(obj, vocab, m)
    if isinstance(obj, list):
        return [mask_obj(v, vocab, pmap) for v in obj]
    if isinstance(obj, dict):
        if obj.get("type") == "image":
            return obj
        return {k: mask_obj(v, vocab, pmap) for k, v in obj.items()}
    return obj


def unmask_obj(obj, tokens=None):
    if tokens is None:
        tokens = privacy_tokens()
    if isinstance(obj, str):
        return unmask_text(obj, tokens)
    if isinstance(obj, list):
        return [unmask_obj(v, tokens) for v in obj]
    if isinstance(obj, dict):
        return {k: unmask_obj(v, tokens) for k, v in obj.items()}
    return obj


def mask_image(path, cfg):
    """Boxes the private details OCR reads in an image file, in place:
    [(placeholder, x, y, width, height)] in its pixels."""
    vocab = privacy_vocab()
    lang = str(cfg.get("ocrLanguages") or "eng")
    if not re.fullmatch(r"[A-Za-z_]+(\+[A-Za-z_]+)*", lang):
        lang = "eng"
    gray = run(["magick", path, "-colorspace", "gray", "pgm:-"], timeout=15, binary=True).stdout
    tsv = run(["tesseract", "stdin", "stdout", "--psm", "11", "-l", lang, "tsv"], input=gray, timeout=30,
              binary=True).stdout.decode(errors="replace")
    found = []
    for row in tsv.splitlines()[1:]:
        f = row.split("\t")
        if len(f) == 12 and f[0] == "5" and f[11].strip():
            found.append((f[11], *map(int, f[6:10])))
    boxes = []
    with PrivacyMap() as m:
        for found in ocr_rows(found):
            line, starts = "", []
            for w in found:
                starts.append(len(line) + (1 if line else 0))
                line += (" " if line else "") + w[0]
            for start, end, spec in privacy_spans(line, vocab):
                hit = [w for w, s in zip(found, starts) if s < end and s + len(w[0]) > start]
                if hit:
                    x0, y0 = min(w[1] for w in hit), min(w[2] for w in hit)
                    x1, y1 = max(w[1] + w[3] for w in hit), max(w[2] + w[4] for w in hit)
                    boxes.append((m.token(spec), x0 - 2, y0 - 2, x1 - x0 + 4, y1 - y0 + 4))
    if boxes:
        draw = [a for b in boxes for a in ("-draw", f"rectangle {b[1]},{b[2]} {b[1] + b[3]},{b[2] + b[4]}")]
        run(["magick", path, "-fill", "black", *draw, path], timeout=15)
    return boxes


def ocr_rows(found):
    """OCR words [(text, x, y, width, height)] as the lines a reader sees:
    tesseract's sparse mode splits a row into blocks (a phone number apart
    from the name before it). Words a row shares, left to right, a line
    while the gap is under twice their height."""
    rows = []
    for w in sorted(found, key=lambda w: w[2] + w[4] / 2):
        mid = w[2] + w[4] / 2
        row = rows[-1] if rows else None
        if row and abs(row[0] - mid) <= max(w[4], row[1]) / 2:
            row[2].append(w)
        else:
            rows.append([mid, w[4], [w]])
    lines = []
    for _, _, ws in rows:
        ws.sort(key=lambda w: w[1])
        line = [ws[0]]
        for w in ws[1:]:
            prev = line[-1]
            if w[1] - (prev[1] + prev[3]) > 2 * max(w[4], prev[4]):
                lines.append(line)
                line = []
            line.append(w)
        lines.append(line)
    return lines


def privacy_note(boxes):
    """What the model is told of the boxes: where each hidden detail is,
    to click it all the same."""
    if not boxes:
        return []
    where = "; ".join(f"{t} at image ({x + w // 2},{y + h // 2})" for t, x, y, w, h in boxes[:30])
    return [text(f"Private details are blacked out in this image: {where}.")]


def privacy_hook():
    """Claude Code's PreToolUse and PostToolUse hook (the side panel's
    Claude): placeholders become the real values in what it sends to any
    tool, and what tools answer is masked."""
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return 0
    answer = privacy_hook_answer(event)
    if answer:
        print(json.dumps(answer, ensure_ascii=False))
    return 0


PRIVACY_PROVIDER_TOOLS = ("WebSearch", "WebFetch")


IMAGE_TYPES = {"image/png": ".png", "image/jpeg": ".jpg", "image/webp": ".webp", "image/gif": ".gif"}


def mask_images(obj):
    """The images in a tool's reply (Read's {type: image, file: {base64,
    type}}, an MCP server's {type: image, data, mimeType}), their private
    details blacked out (ai.privacy.screenshots); the same shape back."""
    if isinstance(obj, list):
        return [mask_images(v) for v in obj]
    if not isinstance(obj, dict):
        return obj
    if obj.get("type") != "image":
        return {k: mask_images(v) for k, v in obj.items()}
    inner = obj.get("file") if isinstance(obj.get("file"), dict) else obj
    key, mime = ("base64", inner.get("type")) if inner is not obj else ("data", obj.get("mimeType"))
    if not isinstance(inner.get(key), str) or mime not in IMAGE_TYPES:
        return obj
    fd, path = tempfile.mkstemp(suffix=IMAGE_TYPES[mime], dir=runtime_dir())
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(base64.b64decode(inner[key]))
        if not mask_image(path, load_config()):
            return obj
        with open(path, "rb") as f:
            data = base64.b64encode(f.read()).decode()
    except (ToolError, ValueError, OSError) as e:
        log(f"privacy: an image left as it is: {e}")
        return obj
    finally:
        with contextlib.suppress(OSError):
            os.unlink(path)
    if inner is obj:
        return {**obj, key: data}
    return {**obj, "file": {**inner, key: data}}


def privacy_hook_answer(event):
    """The hook's answer to an event, or None: nothing to change."""
    if not isinstance(event, dict) or not privacy_on():
        return None
    name = event.get("hook_event_name")
    # WebSearch runs at the model's provider, and WebFetch has its small
    # model read the page with the prompt: a placeholder stays one there.
    if name == "PreToolUse" and event.get("tool_name") in PRIVACY_PROVIDER_TOOLS:
        return None
    if name == "PreToolUse" and isinstance(event.get("tool_input"), dict):
        real = unmask_obj(event["tool_input"])
        if real != event["tool_input"]:
            return {"hookSpecificOutput": {"hookEventName": "PreToolUse", "updatedInput": real}}
    elif name == "PostToolUse" and "tool_response" in event:
        masked = mask_obj(mask_images(event["tool_response"]) if privacy_screenshots() else event["tool_response"])
        if masked != event["tool_response"]:
            return {"hookSpecificOutput": {"hookEventName": "PostToolUse", "updatedToolOutput": masked}}
    return None


# What was sent to a model: each small-model pass (what for, which model,
# the prompt as sent) and the context sent with a question asked in the
# bubble, newest last; SENT_KEEP entries over SENT_DAYS days at most, 0600.
# Settings > Desktop agents > What it sent shows it; `sent clear` empties it.
# Not the side panel's chats: the user wrote those.
SENT_KEEP = 200
SENT_DAYS = 7
SENT_TEXT_MAX = 12000


def sent_path():
    return os.path.join(xdg("XDG_STATE_HOME", "~/.local/state"), "nixbook-shell", "sent.jsonl")


def sent_purpose(system):
    system = system.removesuffix("\n\n" + PRIVACY_PROMPT)
    return {INITIATIVE_SYSTEM: "notifications", CURIOUS_SYSTEM: "curiosity", NEWS_SYSTEM: "news", IDEA_SYSTEM: "a routine idea",
            LEARN_SYSTEM: "memory pass", TIDY_SYSTEM: "memory tidy-up", DLEARN_SYSTEM: "desktop memory pass",
            DTIDY_SYSTEM: "desktop memory tidy-up"}.get(system, "other")


def sent_read():
    try:
        with open(sent_path(), encoding="utf-8") as f:
            entries = [json.loads(ln) for ln in f if ln.strip()]
    except (OSError, ValueError):
        return []
    since = time.time() - SENT_DAYS * 86400
    return [e for e in entries if isinstance(e, dict) and e.get("time", 0) >= since][-SENT_KEEP:]


def sent_note(purpose, model, prompt, web=False):
    """Kept for the user to see; never fails the call it records."""
    entry = {"time": int(time.time()), "purpose": purpose, "model": model, "web": web,
             "local": str(model).startswith("local:"), "text": mask_text(str(prompt), learn=False)[:SENT_TEXT_MAX]}
    path = sent_path()
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        fd = os.open(path, os.O_RDWR | os.O_CREAT, 0o600)
        with os.fdopen(fd, "r+", encoding="utf-8") as f:
            fcntl.flock(f, fcntl.LOCK_EX)
            f.seek(0, os.SEEK_END)
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
            if f.tell() > 2_000_000 or random.random() < 0.05:
                f.flush()
                kept = sent_read()
                f.seek(0)
                f.truncate()
                f.write("".join(json.dumps(e, ensure_ascii=False) + "\n" for e in kept))
    except OSError:
        pass


# Local only (policies.ai 2): the passes that read what happens (curiosity,
# notifications) can use a model running on this computer instead, an
# OpenAI-compatible server on the loopback (Ollama, llama.cpp, LM Studio):
# `localModel: {"url": "http://127.0.0.1:11434/v1", "model": "qwen2.5:7b"}`
# in desktop-mcp.json. Never another host. No web search there.
LOCAL_URL = re.compile(r"^http://(127\.0\.0\.1|localhost|\[::1\])(:\d{1,5})?(/[\w./-]*)?$")


def local_model(cfg):
    lm = cfg.get("localModel")
    if not isinstance(lm, dict):
        return None
    url, model = str(lm.get("url") or "").rstrip("/"), str(lm.get("model") or "")
    return (url, model) if LOCAL_URL.match(url) and model else None


def ask_local_now(cfg, system, prompt, schema=None):
    import urllib.request
    url, model = local_model(cfg)
    body = {"model": model, "stream": False, "temperature": 0.2, "response_format": {"type": "json_object"},
            "messages": [{"role": "system", "content": system + "\nAnswer with one JSON object only, matching: "
                          + json.dumps(schema or LEARN_SCHEMA)},
                         {"role": "user", "content": prompt}]}
    sent_note(sent_purpose(system), f"local:{model}", prompt)
    req = urllib.request.Request(url + "/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=240) as r:
            reply = json.load(r)
        content = reply["choices"][0]["message"]["content"]
    except Exception as e:
        raise ToolError(f"the local model didn't answer: {short(str(e), 200)}")
    start, end = content.find("{"), content.rfind("}")
    try:
        answer = json.loads(content[start:end + 1]) if start >= 0 else None
    except ValueError:
        answer = None
    if not isinstance(answer, dict):
        raise ToolError(f"the local model answered no JSON: {short(content, 200)!r}")
    return answer


def ask_local(cfg, system, prompt, schema=None):
    """The privacy mask: the model reads placeholders, the answer has the
    real values."""
    if not privacy_on():
        return ask_local_now(cfg, system, prompt, schema)
    return unmask_obj(ask_local_now(cfg, system + "\n\n" + PRIVACY_PROMPT, mask_text(prompt), schema))


def model_ready(cfg, hint=None):
    return bool(claude_path(cfg, hint)) if ai_policy() == 1 else ai_policy() == 2 and bool(local_model(cfg))


def ask_model(cfg, hint, system, prompt, schema=None, web=False):
    if ai_policy() == 1:
        claude = claude_path(cfg, hint)
        if not claude:
            raise ToolError("no Claude Code")
        return ask_claude(claude, cfg.get("memoryModel") or "haiku", system, prompt, schema, web)
    if ai_policy() == 2 and local_model(cfg):
        return ask_local(cfg, system, prompt, schema)
    raise ToolError("no model: AI is off, or local only without localModel")


def ask_claude_now(claude, model, system, prompt, schema=None, web=False):
    """One answer from a small model through Claude Code: no tools (with
    `web`, only WebSearch and WebFetch), no MCP servers, no settings, no
    session kept."""
    sent_note(sent_purpose(system), model or "default", prompt, web)
    workdir = os.path.join(xdg("XDG_DATA_HOME", "~/.local/share"), "nixbook-shell", "memory-pass")
    os.makedirs(workdir, mode=0o700, exist_ok=True)
    tools = "WebSearch,WebFetch" if web else ""
    cmd = [claude, "-p", "--output-format", "json", "--no-session-persistence",
           "--strict-mcp-config", "--setting-sources", "project", "--tools", tools,
           "--system-prompt", system, "--json-schema", json.dumps(schema or LEARN_SCHEMA)]
    if web:
        cmd += ["--allowedTools", tools]
    if model:
        cmd += ["--model", model]
    try:
        proc = subprocess.run(cmd, input=prompt, capture_output=True, text=True, cwd=workdir,
                              timeout=420 if web else 180)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise ToolError(f"the memory pass didn't run: {e}")
    if proc.returncode != 0:
        raise ToolError(f"the memory pass failed: {short((proc.stderr or proc.stdout).strip(), 300)}")
    return learn_answer(proc.stdout)


def ask_claude(claude, model, system, prompt, schema=None, web=False):
    """As ask_local, through Claude Code."""
    if not privacy_on():
        return ask_claude_now(claude, model, system, prompt, schema, web)
    return unmask_obj(ask_claude_now(claude, model, system + "\n\n" + PRIVACY_PROMPT, mask_text(prompt), schema, web))


class RoutineJudgments(LockedJson):
    """Topic verdicts per track or title (routine_judge): {items: {item:
    {t, v: {topic hash: bool}}}, day, count}."""
    path = staticmethod(routine_judgments_path)
    keys = ("items",)


def ids_of(answer, key, limit):
    return [i for i in answer.get(key) or [] if isinstance(i, str)][:limit]


def apply_answer(ctx, answer, shown, done, saves, forgets, tidy=False):
    """Applies an answer with the tools' rules. Forgets only entries it was
    shown in full; the tidy-up rewrites without it counting as the subject
    coming up again, and forgets the profile or an important entry only
    when merging it into another of its kind."""
    known = {e["id"]: e for e in read_personal()}
    saved_kinds = set()
    for item in [i for i in answer.get("save") or [] if isinstance(i, dict)][:saves]:
        args = {k: item[k] for k in ("id", "topic", "kind", "date", "text") if isinstance(item.get(k), str) and item[k]}
        level = item.get("importance")
        level = min(max(int(level), 1), 5) if isinstance(level, (int, float)) else None
        if args.get("kind") != "event":
            args.pop("date", None)
        if args.get("id") and args["id"] not in known:
            args.pop("id")  # a made-up id: a new entry, or refused below if the subject exists
        logged = {k: args[k] for k in ("id", "kind") if k in args}
        try:
            t_remember_about_user(ctx, args, weight=level, mention=not tidy)
        except ToolError as e:
            done["skipped"].append(f"{args.get('topic', '?')}: {str(e).splitlines()[0]}")
            audit(ctx.client, "remember_about_user", logged, "error")
            continue
        audit(ctx.client, "remember_about_user", logged, "ok")
        done["saved"].append(args["topic"])
        if args.get("id"):
            saved_kinds.add(args.get("kind", known[args["id"]].get("kind")))
    recalled = [i for i in ids_of(answer, "recalled", 12) if i in known] if not tidy else []
    if recalled:
        with PersonalMemory() as m:
            now = int(time.time())
            for e in m.data["entries"]:
                if e["id"] in recalled:
                    bring_up(e, now)
            m.save()
        done["recalled"] += recalled
    for entry_id in ids_of(answer, "forget", forgets):
        e = known.get(entry_id)
        if entry_id not in shown or not e:
            done["skipped"].append(f"forget {entry_id}: not shown to the pass")
            continue
        if tidy and importance(e) >= 4 and e.get("kind", "topic") not in saved_kinds:
            done["skipped"].append(f"forget {entry_id}: important, and merged into nothing")
            continue
        try:
            t_forget_about_user(ctx, {"id": entry_id})
        except ToolError as e:
            done["skipped"].append(f"forget {entry_id}: {e}")
            continue
        audit(ctx.client, "forget_about_user", {"id": entry_id}, "ok")
        done["forgot"].append(entry_id)


def tidy_due(now):
    """Whether the tidy-up is due; if so, marked as done (a failed one is
    not tried again for a week: no tokens spent on retries)."""
    with PersonalMemory() as m:
        entries, last = m.data["entries"], m.data.get("tidied", 0)
        if now - last < TIDY_DAYS * 86400 or len(entries) < TIDY_MIN_ENTRIES:
            return False
        if last and not any(e.get("updated", 0) > last for e in entries):
            return False
        m.data["tidied"] = int(now)
        m.save()
    return True


def learn_from(cfg, transcript, claude, model, tidy=None):
    """The memory pass on a conversation, then the fading and, when due,
    the tidy-up: {"saved": [topics], "recalled": [ids], "forgot": [ids],
    "faded": [ids], "tidied": bool, "skipped": [why]}. tidy: True to tidy
    now, False never, None when due."""
    done = {"saved": [], "recalled": [], "forgot": [], "faded": [], "tidied": False, "skipped": []}
    now = time.time()
    done["faded"] = fade_personal(now)
    for entry_id in done["faded"]:
        audit(LEARN_CLIENT, "forget_about_user", {"id": entry_id}, "faded")
    ctx = Context(cfg, "cli", LEARN_CLIENT, notify=False)
    transcript = transcript.strip()
    if len(transcript) > LEARN_TRANSCRIPT_MAX:
        transcript = "…" + transcript[-LEARN_TRANSCRIPT_MAX:]
    if transcript:
        prompt, shown = learn_prompt(read_personal(), transcript)
        apply_answer(ctx, ask_claude(claude, model, LEARN_SYSTEM, prompt), shown, done,
                     LEARN_MAX_SAVES, LEARN_MAX_FORGETS)
    if tidy or (tidy is None and tidy_due(now)):
        prompt, shown = tidy_prompt(read_personal())
        try:
            apply_answer(ctx, ask_claude(claude, model, TIDY_SYSTEM, prompt), shown, done,
                         TIDY_MAX_CHANGES, TIDY_MAX_CHANGES, tidy=True)
            done["tidied"] = True
        except ToolError as e:
            done["skipped"].append(f"tidy: {e}")
    return done
