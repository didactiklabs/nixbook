#!/usr/bin/env python3
"""Google Keep sync for nixbook-shell's notes.

The shell's notes (services/Notes.qml) are a JSON list in
$XDG_STATE_HOME/quickshell/user/desktopnotes.txt. This script merges that list
with the user's Google Keep notes (through gkeepapi, the unofficial Keep API
client) and hands the merged list back.

Commands (each answers one JSON object on stdout):

  status    {"configured": bool, "email": str, "lastSync": ms, "error": str}
  login     the account's email and its master token on stdin (two lines);
            they go to the keyring (secret-tool) and are checked against Keep
  logout    forgets the account
  sync      the notes on stdin ({"notes": [...]}), the merged notes on stdout
            ({"notes": [...], "stats": {...}, "error": str})

The credentials never touch the disk in clear: they live in the keyring, under
application=nixbook-keep kind=google-keep. NIXBOOK_KEEP_SECRETS_DIR keeps them
in files instead, for the tests only.

The merge is a pure function of the two lists (merge_notes below), so it can
be tested without an account: gkeepapi is imported only when a sync actually
runs.

How a note maps to a Keep note:

  - the note's first non-empty line is Keep's title, the rest its text;
  - a note whose lines are all "- [ ] item" / "- [x] item" is a Keep list
    (a checklist), the other notes are Keep notes;
  - "pinned" is Keep's pin;
  - the note's id and the Keep note's id are kept together ("keepId"), with
    the Keep timestamp of the last sync ("keepEdited"), to tell which side
    changed.

Deletions are not synced: a note deleted in the shell stays in Keep, a note
deleted in Keep stays in the shell, and neither is brought back. The Keep
notes whose shell note is gone are remembered in the sync state, so they are
not imported again.
"""

import json
import os
import random
import re
import subprocess
import sys
import time

# A checklist line: "- [ ] milk", "* [x] eggs", "• [ ] bread".
CHECKLIST_RE = re.compile(r"^\s*[-*•]?\s*\[([ xX])\]\s*(.*)$")

# Exit codes (the shell reads them).
EXIT_OK = 0
EXIT_USAGE = 1
EXIT_NOT_CONFIGURED = 2
EXIT_AUTH = 3
EXIT_NETWORK = 4
EXIT_ERROR = 5

SECRET_APPLICATION = "nixbook-keep"
SECRET_KIND = "google-keep"


# -- Where things live -------------------------------------------------------


def state_dir():
    """The shell's state directory (where the sync state and the cache are)."""
    state = os.environ.get("XDG_STATE_HOME") or os.path.join(
        os.path.expanduser("~"), ".local", "state"
    )
    return os.path.join(state, "nixbook-shell")


def state_path():
    return os.path.join(state_dir(), "keep-sync.json")


def cache_path():
    return os.path.join(state_dir(), "keep-cache.json")


# -- The credentials (the keyring) -------------------------------------------


def write_private(path, text):
    """Writes a file only the user can read (0600 from its creation, not
    chmod-ed afterwards), atomically: a temporary file renamed over it."""
    tmp = path + ".new"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    # O_CREAT's mode doesn't change a .new left over by an older version.
    os.fchmod(fd, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        handle.write(text)
    os.replace(tmp, path)


def secret_tool(args, stdin=None):
    """Runs secret-tool; returns (code, stdout, stderr)."""
    try:
        proc = subprocess.run(
            ["secret-tool", *args],
            input=stdin,
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
    except FileNotFoundError:
        return 127, "", "secret-tool (libsecret) isn't installed"
    except subprocess.TimeoutExpired:
        return 124, "", "the keyring didn't answer: is it unlocked?"
    return proc.returncode, proc.stdout, proc.stderr


def secrets_dir():
    """A directory holding the secrets instead of the keyring (the tests)."""
    return os.environ.get("NIXBOOK_KEEP_SECRETS_DIR")


def load_credentials():
    """The stored {email, token}, or None."""
    directory = secrets_dir()
    if directory:
        path = os.path.join(directory, SECRET_KIND)
        try:
            with open(path, encoding="utf-8") as handle:
                data = json.load(handle)
        except (OSError, ValueError):
            return None
        if data.get("email") and data.get("token"):
            return data
        return None
    code, out, _ = secret_tool(
        ["lookup", "application", SECRET_APPLICATION, "kind", SECRET_KIND]
    )
    if code != 0:
        return None
    try:
        data = json.loads(out)
    except ValueError:
        return None
    if not data.get("email") or not data.get("token"):
        return None
    return data


def save_credentials(email, token):
    """Stores the credentials; raises on failure."""
    data = json.dumps({"email": email, "token": token})
    directory = secrets_dir()
    if directory:
        os.makedirs(directory, exist_ok=True)
        write_private(os.path.join(directory, SECRET_KIND), data)
        return
    code, _, err = secret_tool(
        [
            "store",
            "--label=nixbook-keep: Google Keep",
            "application",
            SECRET_APPLICATION,
            "kind",
            SECRET_KIND,
        ],
        stdin=data,
    )
    if code != 0:
        raise RuntimeError(err.strip() or "the keyring refused the secret")


def clear_credentials():
    """Forgets the credentials."""
    directory = secrets_dir()
    if directory:
        path = os.path.join(directory, SECRET_KIND)
        try:
            os.remove(path)
        except OSError:
            pass
        return
    secret_tool(
        ["clear", "application", SECRET_APPLICATION, "kind", SECRET_KIND]
    )


# -- The sync state ----------------------------------------------------------


def load_state():
    """The sync state {lastSync, mapping, ignored}, or a fresh one."""
    fresh = {"lastSync": 0, "mapping": {}, "ignored": []}
    try:
        with open(state_path(), encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError):
        return fresh
    if not isinstance(data, dict):
        return fresh
    fresh["lastSync"] = data.get("lastSync") or 0
    mapping = data.get("mapping")
    fresh["mapping"] = mapping if isinstance(mapping, dict) else {}
    ignored = data.get("ignored")
    fresh["ignored"] = [i for i in ignored if isinstance(i, str)] if isinstance(ignored, list) else []
    return fresh


def save_state(state):
    """Writes the sync state."""
    os.makedirs(state_dir(), exist_ok=True)
    write_private(state_path(), json.dumps(state))


def load_cache():
    """The Keep state cached on disk (the notes, not the credentials)."""
    try:
        with open(cache_path(), encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None


def save_cache(cache):
    """Caches the Keep state, so the next sync doesn't download everything."""
    if not cache:
        return
    try:
        os.makedirs(state_dir(), exist_ok=True)
        write_private(cache_path(), json.dumps(cache))
    except OSError:
        pass  # a cache we can't write is not worth failing the sync for


# -- The notes' content ------------------------------------------------------


def parse_note(content):
    """The content of a note as (title, body, items).

    The title is the first non-empty line (what the Notes app shows as the
    note's title), the body the rest. A note whose lines are all checklist
    lines is a list: items is [(text, checked)], the body None. A note whose
    first line is a checklist line is a list without a title.
    """
    lines = (content or "").split("\n")
    title = ""
    rest = []
    for index, line in enumerate(lines):
        if line.strip() == "":
            continue
        if CHECKLIST_RE.match(line):
            # A checklist: every line is an item, the note has no title.
            rest = lines[index:]
            title = ""
        else:
            title = line.strip()
            rest = lines[index + 1 :]
        break
    else:
        rest = []

    body_lines = [line for line in rest if line.strip() != ""]
    if body_lines and all(CHECKLIST_RE.match(line) for line in body_lines):
        items = []
        for line in body_lines:
            match = CHECKLIST_RE.match(line)
            items.append((match.group(2).strip(), match.group(1).lower() == "x"))
        return title, None, items
    return title, "\n".join(rest), None


def render_note(title, body, items):
    """The content of a note from (title, body, items) — the inverse of
    parse_note."""
    title = (title or "").strip()
    if items is not None:
        lines = [f"- [{'x' if checked else ' '}] {text}" for text, checked in items]
        return "\n".join(([title] if title else []) + lines)
    body = body or ""
    if body.strip() == "":
        return title
    return "\n".join(([title] if title else []) + body.split("\n"))


# -- The merge ---------------------------------------------------------------


def remote_content(remote):
    """The content of a remote (Keep) note."""
    if remote.get("items") is not None:
        return render_note(remote.get("title", ""), None, remote["items"])
    return render_note(remote.get("title", ""), remote.get("text", ""), None)


def new_local_id():
    """An id for a note that came from Keep (the Notes app's own shape:
    the time in ms and a random number, so two notes imported in the same
    millisecond don't share an id)."""
    return f"{int(time.time() * 1000)}-{random.randrange(10000)}"


def merge_notes(local_notes, remote_notes, push=True, pull=True, ignored=()):
    """Merges the shell's notes with Keep's.

    Returns (merged, actions, stats). The merged list is what the shell keeps;
    the actions are what has to happen on Keep's side (push a note, create
    one), for the caller to do.

    The rules:
      - a note with a Keep note: the side that changed since the last sync
        wins; if both changed, the newer one does;
      - a note without one: it is created in Keep (push) or linked to an
        identical Keep note (the first sync, when the notes are already
        there);
      - a Keep note without a shell note: it is imported (pull), unless it is
        in `ignored` (its shell note was deleted) or trashed;
      - a note whose Keep note is gone (deleted in Keep) stays here, and is
        not created again.
    """
    remote_by_id = {remote["id"]: remote for remote in remote_notes}
    # Each Keep note's content, rendered once (the twin search and the
    # imports compare against it).
    contents = {remote["id"]: remote_content(remote) for remote in remote_notes}
    ignored = set(ignored or ())
    merged = []
    actions = []
    stats = {
        "pushed": 0,
        "pulled": 0,
        "created": 0,
        "imported": 0,
        "linked": 0,
        "conflicts": 0,
        "skipped": 0,
    }
    used_remote = set()

    for original in local_notes:
        note = dict(original)
        note_id = note.get("id") or new_local_id()
        note["id"] = note_id
        content = note.get("content") or ""
        pinned = bool(note.get("pinned"))
        keep_id = note.get("keepId") or ""

        if not keep_id:
            # A note that isn't in Keep yet: an identical Keep note (the
            # first sync) takes it, else it is created there.
            twin = _find_twin(content, remote_notes, contents, used_remote)
            if twin is None:
                if push:
                    title, body, items = parse_note(content)
                    actions.append(
                        {
                            "op": "create",
                            "localId": note_id,
                            "title": title,
                            "text": body or "",
                            "items": items,
                            "pinned": pinned,
                        }
                    )
                    stats["created"] += 1
                else:
                    stats["skipped"] += 1
                merged.append(note)
                continue
            used_remote.add(twin["id"])
            keep_id = twin["id"]
            note["keepId"] = keep_id
            note["keepEdited"] = twin.get("edited") or 0
            actions.append({"op": "link", "localId": note_id, "keepId": keep_id})
            stats["linked"] += 1

        remote = remote_by_id.get(keep_id)
        if remote is None:
            # Deleted (or trashed) in Keep: the note stays here, nothing is
            # pushed and nothing is brought back.
            stats["skipped"] += 1
            merged.append(note)
            continue

        used_remote.add(keep_id)
        remote_text = contents[keep_id]
        remote_pinned = bool(remote.get("pinned"))
        last = note.get("keepEdited") or 0
        local_changed = (note.get("updatedAt") or 0) > last
        remote_changed = (remote.get("edited") or 0) > last

        if content == remote_text and pinned == remote_pinned:
            # The same on both sides: only the timestamp moves.
            note["keepEdited"] = remote.get("edited") or 0
            merged.append(note)
            continue

        if local_changed and remote_changed:
            stats["conflicts"] += 1
        take_remote = remote_changed and (
            not local_changed or (remote.get("edited") or 0) > (note.get("updatedAt") or 0)
        )

        if take_remote:
            note["content"] = remote_text
            note["pinned"] = remote_pinned
            edited = remote.get("edited") or 0
            created = remote.get("created") or 0
            if created:
                note["createdAt"] = created
            note["updatedAt"] = max(note.get("updatedAt") or 0, edited)
            note["keepEdited"] = remote.get("edited") or 0
            stats["pulled"] += 1
        else:
            title, body, items = parse_note(content)
            actions.append(
                {
                    "op": "push",
                    "localId": note_id,
                    "keepId": keep_id,
                    "title": title,
                    "text": body or "",
                    "items": items,
                    "pinned": pinned,
                    "list": bool(remote.get("items") is not None),
                }
            )
            note["keepEdited"] = remote.get("edited") or 0
            stats["pushed"] += 1
        merged.append(note)

    # The Keep notes that aren't here yet.
    for remote in remote_notes:
        if remote["id"] in used_remote or remote["id"] in ignored:
            continue
        if remote.get("trashed") or remote.get("deleted"):
            continue
        if not pull:
            stats["skipped"] += 1
            continue
        content = contents[remote["id"]]
        if content.strip() == "":
            continue
        note = {
            "id": new_local_id(),
            "content": content,
            "attachments": [],
            "createdAt": remote.get("created") or int(time.time() * 1000),
            "updatedAt": remote.get("edited") or remote.get("created") or int(time.time() * 1000),
            "pinned": bool(remote.get("pinned")),
            "keepId": remote["id"],
            "keepEdited": remote.get("edited") or 0,
        }
        merged.append(note)
        actions.append({"op": "import", "localId": note["id"], "keepId": remote["id"]})
        stats["imported"] += 1

    return merged, actions, stats


def _find_twin(content, remote_notes, contents, used_remote):
    """A Keep note with exactly this content (the first sync: the notes are
    already in Keep, they just aren't linked yet)."""
    for remote in remote_notes:
        if remote["id"] in used_remote:
            continue
        if remote.get("trashed") or remote.get("deleted"):
            continue
        if contents[remote["id"]] == content:
            return remote
    return None


# -- Keep itself -------------------------------------------------------------


def to_remote(node):
    """A Keep node as the plain data the merge works on."""
    timestamps = node.timestamps
    edited = _ms(timestamps.edited) or _ms(timestamps.updated) or 0
    created = _ms(timestamps.created) or 0
    items = None
    if hasattr(node, "items"):
        items = [(item.text or "", bool(item.checked)) for item in node.items]
    return {
        "id": node.id,
        "title": node.title or "",
        "text": node.text or "",
        "items": items,
        "pinned": bool(node.pinned),
        "created": created,
        "edited": edited,
        "trashed": bool(getattr(node, "trashed", False)),
        "deleted": bool(getattr(node, "deleted", False)),
    }


def _ms(when):
    """A datetime as milliseconds since the epoch."""
    if when is None:
        return 0
    try:
        return int(when.timestamp() * 1000)
    except (AttributeError, OSError, OverflowError, ValueError):
        return 0


def authenticate(credentials, cache=None):
    """A Keep client for this account (raises on a bad token)."""
    try:
        import gkeepapi  # imported here: the merge is testable without it
    except ImportError:
        raise SyncError(
            "gkeepapi isn't installed (the shell's package is broken)", EXIT_ERROR
        )

    keep = gkeepapi.Keep()
    keep.authenticate(
        credentials["email"], credentials["token"], state=cache, sync=True
    )
    return keep


def apply_action(keep, action):
    """Does one action on Keep's side; returns the node (or None)."""
    if action["op"] == "create":
        if action.get("items") is not None:
            # createList keeps the items in the order they are given.
            node = keep.createList(action.get("title") or "", action.get("items") or [])
        else:
            node = keep.createNote(action.get("title") or "", action.get("text") or "")
        node.pinned = bool(action.get("pinned"))
        return node
    if action["op"] == "push":
        node = keep.get(action["keepId"])
        if node is None:
            return None
        if action.get("items") is not None and hasattr(node, "items"):
            _push_list(node, action)
        else:
            title = action.get("title") or ""
            text = action.get("text") or ""
            # Only what changed: a setter marks the note dirty, and a note
            # marked dirty is uploaded again.
            if node.title != title:
                node.title = title
            if node.text != text:
                node.text = text
        pinned = bool(action.get("pinned"))
        if bool(node.pinned) != pinned:
            node.pinned = pinned
        return node
    return None


def _push_list(node, action):
    """Writes the items of a checklist into a Keep list."""
    import gkeepapi

    items = action.get("items") or []
    current = list(node.items)
    for index, item in enumerate(current):
        if index >= len(items):
            node.remove(item, True)
            continue
        text, checked = items[index]
        if item.text != text:
            item.text = text
        if bool(item.checked) != bool(checked):
            item.checked = checked
    # The new items go last (a random place otherwise).
    for text, checked in items[len(current) :]:
        node.add(text, checked, gkeepapi.node.NewListItemPlacementValue.Bottom)


def do_sync(local_notes, push=True, pull=True):
    """The sync: the merged notes and what happened."""
    credentials = load_credentials()
    if not credentials:
        raise SyncError("no Google Keep account yet", EXIT_NOT_CONFIGURED)

    try:
        keep = authenticate(credentials, load_cache())
    except SyncError:
        raise
    except Exception as error:  # gkeepapi raises its own exceptions
        raise SyncError(_auth_message(error), EXIT_AUTH)

    state = load_state()
    remote_notes = [to_remote(node) for node in keep.all()]
    local_keep_ids = {
        note.get("keepId") for note in local_notes if note.get("keepId")
    }

    # The notes whose shell note is gone: not imported again.
    ignored = set(state.get("ignored") or [])
    for keep_id in state.get("mapping", {}):
        if keep_id not in local_keep_ids:
            ignored.add(keep_id)
    ignored -= local_keep_ids

    merged, actions, stats = merge_notes(
        local_notes, remote_notes, push=push, pull=pull, ignored=ignored
    )

    # The pushes and the creations, on Keep's side.
    by_id = {note.get("id"): note for note in merged}
    changed = False
    for action in actions:
        if action["op"] not in ("create", "push"):
            continue
        try:
            node = apply_action(keep, action)
        except Exception as error:
            raise SyncError(f"Keep refused the change: {error}", EXIT_NETWORK)
        if node is None:
            continue
        changed = True
        note = by_id.get(action["localId"])
        if note is None:
            continue
        if action["op"] == "create":
            note["keepId"] = node.id
        # The note was changed on Keep's side: the next sync compares with
        # this moment, not with the one before the change.
        note["keepEdited"] = _ms(node.timestamps.edited)
    if changed:
        keep.sync()

    # The state: what is linked to what, and what is not to be imported.
    mapping = {}
    for note in merged:
        keep_id = note.get("keepId")
        if keep_id:
            mapping[keep_id] = note["id"]
    state["mapping"] = mapping
    state["ignored"] = sorted(ignored)
    state["lastSync"] = int(time.time() * 1000)
    save_state(state)

    try:
        save_cache(keep.dump())
    except Exception:
        pass

    stats["lastSync"] = state["lastSync"]
    return merged, stats


class SyncError(Exception):
    """A sync that couldn't be done (the message is for the user)."""

    def __init__(self, message, code=EXIT_ERROR):
        super().__init__(message)
        self.code = code


def _auth_message(error):
    """What to say about a failed authentication."""
    text = str(error)
    if "BadAuthentication" in text or "Invalid" in text:
        return "Google refused the account: the master token is not valid"
    if "CaptchaRequired" in text:
        return "Google wants a captcha: the master token was refused"
    if "NeedsBrowser" in text:
        return "Google wants a browser sign-in: the master token was refused"
    if "DeviceManagement" in text:
        return "Google's device policy blocks this account"
    return f"the sign-in failed: {text}"


# -- The commands ------------------------------------------------------------


def command_status():
    credentials = load_credentials()
    state = load_state()
    return {
        "configured": credentials is not None,
        "email": credentials["email"] if credentials else "",
        "lastSync": state.get("lastSync") or 0,
        "error": "",
    }


def command_login():
    """The email and the master token on stdin (two lines)."""
    lines = sys.stdin.read().split("\n")
    email = lines[0].strip() if lines else ""
    token = lines[1].strip() if len(lines) > 1 else ""
    if not email or not token:
        raise SyncError("the email and the master token are needed", EXIT_USAGE)
    save_credentials(email, token)
    # Checked right away: a wrong token is said now, not at the next sync.
    try:
        keep = authenticate(load_credentials())
    except SyncError:
        raise
    except Exception as error:
        clear_credentials()
        raise SyncError(_auth_message(error), EXIT_AUTH)
    state = load_state()
    state["lastSync"] = int(time.time() * 1000)
    save_state(state)
    try:
        save_cache(keep.dump())
    except Exception:
        pass
    return {"configured": True, "email": email, "lastSync": state["lastSync"], "error": ""}


def command_logout():
    clear_credentials()
    return {"configured": False, "email": "", "lastSync": load_state().get("lastSync") or 0, "error": ""}


def command_sync():
    """The notes on stdin, the merged notes on stdout."""
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except ValueError:
        raise SyncError("the notes sent were not readable", EXIT_USAGE)
    notes = payload.get("notes") if isinstance(payload, dict) else payload
    if not isinstance(notes, list):
        raise SyncError("no notes to sync", EXIT_USAGE)
    push = payload.get("push", True) if isinstance(payload, dict) else True
    pull = payload.get("pull", True) if isinstance(payload, dict) else True
    merged, stats = do_sync(notes, push=bool(push), pull=bool(pull))
    return {"notes": merged, "stats": stats, "error": ""}


COMMANDS = {
    "status": command_status,
    "login": command_login,
    "logout": command_logout,
    "sync": command_sync,
}


def main(argv):
    if len(argv) < 2 or argv[1] not in COMMANDS:
        sys.stderr.write(
            "Usage: nixbook-keep status|login|logout|sync\n"
        )
        return EXIT_USAGE
    try:
        answer = COMMANDS[argv[1]]()
        code = EXIT_OK
    except SyncError as error:
        answer = {"error": str(error)}
        code = error.code
    except Exception as error:  # never a traceback on stdout
        sys.stderr.write(f"nixbook-keep: {error}\n")
        answer = {"error": str(error)}
        code = EXIT_ERROR
    sys.stdout.write(json.dumps(answer))
    sys.stdout.write("\n")
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv))
