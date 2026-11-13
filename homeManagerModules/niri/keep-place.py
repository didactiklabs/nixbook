"""niri-keep-place: give a reopened window the place of the one it replaces.

Some apps close their window and open a new one in its place: Moonlight
hides its window while a game streams and opens a stream window, then the
reverse when the game ends; Vesktop quits and starts again on its own
(updates, the Electron bridge). niri sees a brand-new window each time and
opens it at the default width, next to whatever has focus, on the focused
workspace.

This follows niri's event stream and, when a window of a watched app opens
while another window of that app is open or closed less than GRACE seconds
ago, moves it to that window's workspace, makes it floating or tiled like
it, gives it its size, and puts it at its column (when it has the focus:
niri only moves the focused column) or floating position. Nothing is kept
longer, nor on disk: an app launched later opens like any other window. An
app given titles only counts windows whose title matches one of them (its
main window, not a splash or popouts).

Usage: niri-keep-place CONFIG.json
  CONFIG = {"apps": {"<app id>": {"titles": ["<regex>", ...]}, ...}}
"""

import json
import os
import re
import socket
import sys
import time

GRACE = 30.0  # seconds a closed window's place is kept (Vesktop restarting)
SETTLE = 0.4  # seconds for the client to take a new size before reading back


def log(*args):
    print(*args, file=sys.stderr, flush=True)


def request(body):
    """One request on a fresh connection: niri answers one line per request."""
    with socket.socket(socket.AF_UNIX) as s:
        s.connect(os.environ["NIRI_SOCKET"])
        s.sendall((json.dumps(body) + "\n").encode())
        s.shutdown(socket.SHUT_WR)
        reply = json.loads(s.makefile().readline())
    if "Err" in reply:
        raise RuntimeError(f"{body}: {reply['Err']}")
    return reply["Ok"]


def action(name, **fields):
    request({"Action": {name: fields}})


def windows():
    return {w["id"]: w for w in request("Windows")["Windows"]}


def focused_id():
    w = request("FocusedWindow")["FocusedWindow"]
    return w["id"] if w else None


def focus_time(w):
    t = w.get("focus_timestamp") or {}
    return (t.get("secs", 0), t.get("nanos", 0))


def size_of(w):
    return w["layout"]["window_size"]


def find_workspace(ref, workspaces):
    """The remembered workspace, if it still exists (niri removes an emptied
    one when you're not on it)."""
    return ref["workspace_id"] if ref["workspace_id"] in workspaces else None


def restore(new_id, ref, workspaces):
    win = windows().get(new_id)
    if not win:
        return
    lay = ref["layout"]
    what = []

    target = find_workspace(ref, workspaces)
    if target is None:
        what.append("workspace gone, left where it opened")
    elif target != win["workspace_id"]:
        action(
            "MoveWindowToWorkspace",
            window_id=new_id,
            reference={"Id": target},
            focus=win["is_focused"],
        )
        what.append(f"workspace {target}")

    if ref["is_floating"] != win["is_floating"]:
        action("MoveWindowToFloating" if ref["is_floating"] else "MoveWindowToTiling", id=new_id)
        what.append("floating" if ref["is_floating"] else "tiled")

    want_w, want_h = size_of(ref)
    pos = lay.get("tile_pos_in_workspace_view") if ref["is_floating"] else None

    def apply(dw=0, dh=0, dx=0.0, dy=0.0):
        action("SetWindowWidth", id=new_id, change={"SetFixed": round(want_w + dw)})
        if ref["is_floating"]:
            action("SetWindowHeight", id=new_id, change={"SetFixed": round(want_h + dh)})
            if pos:
                action(
                    "MoveFloatingWindow",
                    id=new_id,
                    x={"SetFixed": pos[0] + dx},
                    y={"SetFixed": pos[1] + dy},
                )

    # niri's fixed sizes and floating positions don't count the same things
    # as what it reports (borders, the working area's origin): set them, read
    # back what came out, and correct once by the difference.
    apply()
    time.sleep(SETTLE)
    now = windows().get(new_id)
    if now:
        got_w, got_h = size_of(now)
        npos = now["layout"].get("tile_pos_in_workspace_view")
        dw = want_w - got_w
        dh = (want_h - got_h) if ref["is_floating"] else 0
        dx = (pos[0] - npos[0]) if pos and npos else 0.0
        dy = (pos[1] - npos[1]) if pos and npos else 0.0
        if max(abs(dw), abs(dh), abs(dx), abs(dy)) > 1:
            apply(dw, dh, dx, dy)
    what.append(f"{want_w}x{want_h}" if ref["is_floating"] else f"width {want_w}")
    if pos:
        what.append(f"at {pos[0]:.0f},{pos[1]:.0f}")

    # The column order: niri can only move the focused column, so only when
    # the new window has the focus (a new window normally takes it), and only
    # on the remembered workspace.
    col = (lay.get("pos_in_scrolling_layout") or [None])[0]
    if not ref["is_floating"] and col and target is not None:
        if focused_id() == new_id:
            action("MoveColumnToIndex", index=col)
            what.append(f"column {col}")

    log(f"{win['app_id']} window {new_id} ({win['title']!r}): {', '.join(what)}")


def main():
    if len(sys.argv) != 2 or not os.environ.get("NIRI_SOCKET"):
        log("usage: niri-keep-place CONFIG.json (inside a niri session)")
        return 2
    with open(sys.argv[1]) as f:
        apps = {
            app: [re.compile(t) for t in (opts or {}).get("titles", [])]
            for app, opts in json.load(f)["apps"].items()
        }

    def watched(w):
        rules = apps.get(w["app_id"])
        if rules is None:
            return False
        return not rules or any(r.search(w.get("title") or "") for r in rules)

    closed = {}  # app_id -> (window, closed at)
    seen = {}  # id -> last known window of a watched app (title matching)
    placed = set()  # ids already given a place: never moved twice
    workspaces = {}

    with socket.socket(socket.AF_UNIX) as s:
        s.connect(os.environ["NIRI_SOCKET"])
        s.sendall(b'"EventStream"\n')
        stream = s.makefile()
        if "Ok" not in json.loads(stream.readline()):
            log("niri refused the event stream")
            return 1
        log(f"watching {', '.join(sorted(apps))}")
        for line in stream:
            event = json.loads(line)
            if "WorkspacesChanged" in event:
                workspaces = {w["id"]: w for w in event["WorkspacesChanged"]["workspaces"]}
            elif "WindowsChanged" in event:  # the full list, at start
                seen = {w["id"]: w for w in event["WindowsChanged"]["windows"] if watched(w)}
                placed = {w["id"] for w in event["WindowsChanged"]["windows"]}
            elif "WindowOpenedOrChanged" in event:
                w = event["WindowOpenedOrChanged"]["window"]
                if not watched(w):
                    seen.pop(w["id"], None)  # its title no longer matches
                elif w["id"] in seen or w["id"] in placed:
                    # Known: follow it (a title that matches again isn't new).
                    seen[w["id"]] = w
                else:
                    # New: the place of another window of the app still open
                    # (the new one may come first), else of the one that
                    # just closed.
                    others = [o for o in seen.values() if o["app_id"] == w["app_id"]]
                    ref = max(others, key=focus_time, default=None)
                    last, at = closed.get(w["app_id"], (None, 0.0))
                    if ref is None and time.monotonic() - at < GRACE:
                        ref = last
                    ref = json.loads(json.dumps(ref)) if ref else None
                    seen[w["id"]] = w
                    placed.add(w["id"])
                    if ref:
                        try:
                            restore(w["id"], ref, workspaces)
                        except (OSError, RuntimeError, KeyError, TypeError) as e:
                            log(f"window {w['id']}: {e}")
            elif "WindowLayoutsChanged" in event:
                for wid, layout in event["WindowLayoutsChanged"]["changes"]:
                    if wid in seen:
                        seen[wid]["layout"] = layout
            elif "WindowClosed" in event:
                w = seen.pop(event["WindowClosed"]["id"], None)
                placed.discard(event["WindowClosed"]["id"])
                if w:
                    closed[w["app_id"]] = (w, time.monotonic())
    log("niri closed the event stream")
    return 1


if __name__ == "__main__":
    sys.exit(main())
