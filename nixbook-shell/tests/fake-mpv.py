#!/usr/bin/env python3
"""A stand-in for mpv in tests/ytmusic.sh: its JSON IPC (the commands
nixbook-ytmusic sends), no audio. Each file "plays" FAKE_MPV_LEN seconds
(default 2; FAKE_MPV_LEN_FILE, read as it plays, wins) then ends (end-file
eof); a URL with "fail" in it ends with an error. Every loadfile is logged to FAKE_MPV_LOG as one JSON line."""
import json
import os
import socket
import sys
import threading
import time

path = next(a.split("=", 1)[1] for a in sys.argv[1:] if a.startswith("--input-ipc-server="))
LENGTH_FILE = os.environ.get("FAKE_MPV_LEN_FILE")


def length():
    """How long a file plays: FAKE_MPV_LEN_FILE's number when there (read
    at each check: a test can change it), else FAKE_MPV_LEN (2)."""
    try:
        with open(LENGTH_FILE) as f:
            return float(f.read().strip())
    except (TypeError, OSError, ValueError):
        return float(os.environ.get("FAKE_MPV_LEN", "2"))


log = os.environ.get("FAKE_MPV_LOG")
state = {"url": None, "start": 0.0, "at": 0.0, "pause": False, "gen": 0}
lock = threading.Lock()
clients = []


def send(conn, msg):
    try:
        conn.sendall(json.dumps(msg).encode() + b"\n")
    except OSError:
        pass


def event(msg):
    for c in list(clients):
        send(c, msg)


def pos():
    if state["url"] is None:
        return None
    return state["start"] + (0 if state["pause"] else time.monotonic() - state["at"])


def play(url, start, gen):
    time.sleep(0.2)
    with lock:
        if gen != state["gen"]:
            return
    if "fail" in url:
        event({"event": "end-file", "reason": "error", "file_error": "loading failed"})
        return
    event({"event": "file-loaded"})
    while True:
        time.sleep(0.05)
        with lock:
            if gen != state["gen"]:
                return
            if not state["pause"] and pos() >= length():
                state["url"] = None
                break
    event({"event": "end-file", "reason": "eof"})


def handle(conn, msg):
    cmd = msg.get("command") or []
    rid = msg.get("request_id")
    data = None
    if cmd[:1] == ["loadfile"]:
        opts = dict(o.split("=", 1) for o in (cmd[4] if len(cmd) > 4 else "").split(",") if "=" in o)
        with lock:
            state["gen"] += 1
            state.update(url=cmd[1], start=float(opts.get("start", 0)), at=time.monotonic(), pause=False)
            gen = state["gen"]
        if log:
            with open(log, "a") as f:
                f.write(json.dumps({"url": cmd[1], "opts": cmd[4] if len(cmd) > 4 else ""}) + "\n")
        threading.Thread(target=play, args=(cmd[1], state["start"], gen), daemon=True).start()
    elif cmd[:2] == ["get_property", "time-pos"]:
        data = pos()
    elif cmd[:2] == ["set_property", "pause"]:
        with lock:
            p = pos()
            state.update(pause=bool(cmd[2]), start=p or 0.0, at=time.monotonic())
        event({"event": "property-change", "name": "pause", "data": bool(cmd[2])})
    elif cmd[:1] == ["seek"]:
        with lock:
            state.update(start=float(cmd[1]), at=time.monotonic())
    send(conn, {"request_id": rid, "error": "success", "data": data})


def serve(conn):
    clients.append(conn)
    buf = b""
    while True:
        try:
            chunk = conn.recv(65536)
        except OSError:
            break
        if not chunk:
            break
        buf += chunk
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            try:
                handle(conn, json.loads(line))
            except (ValueError, KeyError, IndexError, TypeError):
                pass
    clients.remove(conn)


s = socket.socket(socket.AF_UNIX)
s.bind(path)
s.listen(4)
while True:
    c, _ = s.accept()
    threading.Thread(target=serve, args=(c,), daemon=True).start()
