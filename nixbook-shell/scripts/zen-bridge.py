"""nixbook-zen-bridge: the native messaging host of nixbook's Zen extension
(zen/), between it and the desktop agents' tools (nixbook-desktop-mcp's
page_*).

Zen starts it when the extension connects (native messaging: one JSON
message per frame, a 4-byte native-endian length first, on stdin/stdout)
and stops it with the browser. It listens on a Unix socket only this user
can reach, $XDG_RUNTIME_DIR/nixbook-zen/bridge.sock (directory 0700, socket
0600): a client sends one JSON request per line ({cmd, …}), gets the
extension's answer as one line ({ok, result} or {ok: false, error}), and may
send more on the same connection.

  nixbook-zen-bridge [MANIFEST_PATH EXTENSION_ID]   (as Zen starts it)
  nixbook-zen-bridge --socket                       (prints the socket path)
"""

import itertools
import json
import os
import socket
import struct
import sys
import threading

TIMEOUT = 45.0
MAX_LINE = 4 * 1024 * 1024


def socket_path():
    base = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    return os.path.join(base, "nixbook-zen", "bridge.sock")


class Bridge:
    def __init__(self, out):
        self.out = out
        self.write_lock = threading.Lock()
        self.pending = {}
        self.ids = itertools.count(1)
        self.lock = threading.Lock()

    def send(self, msg):
        data = json.dumps(msg).encode()
        with self.write_lock:
            self.out.write(struct.pack("=I", len(data)) + data)
            self.out.flush()

    def ask(self, request):
        """One request to the extension, its answer (or an error)."""
        rid = next(self.ids)
        done = threading.Event()
        slot = {"event": done}
        with self.lock:
            self.pending[rid] = slot
        try:
            self.send({**request, "id": rid})
            if not done.wait(TIMEOUT):
                return {"ok": False, "error": f"Zen didn't answer within {int(TIMEOUT)} s"}
            return slot["reply"]
        finally:
            with self.lock:
                self.pending.pop(rid, None)

    def answered(self, msg):
        with self.lock:
            slot = self.pending.get(msg.get("id"))
        if slot:
            slot["reply"] = {k: v for k, v in msg.items() if k != "id"}
            slot["event"].set()


def read_messages(stream, bridge):
    """The extension's answers, until Zen closes the pipe."""
    while True:
        head = stream.read(4)
        if len(head) < 4:
            return
        (size,) = struct.unpack("=I", head)
        body = stream.read(size)
        if len(body) < size:
            return
        try:
            bridge.answered(json.loads(body))
        except ValueError:
            continue


def serve_client(conn, bridge):
    with conn:
        f = conn.makefile("rwb")
        for line in f:
            if len(line) > MAX_LINE:
                break
            try:
                request = json.loads(line)
                if not isinstance(request, dict) or not isinstance(request.get("cmd"), str):
                    raise ValueError
                reply = bridge.ask(request)
            except ValueError:
                reply = {"ok": False, "error": "a request is one JSON object per line, with its cmd"}
            try:
                f.write(json.dumps(reply).encode() + b"\n")
                f.flush()
            except OSError:
                return


def main(argv):
    if "--socket" in argv:
        print(socket_path())
        return 0
    path = socket_path()
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    os.chmod(os.path.dirname(path), 0o700)
    try:
        os.unlink(path)  # one Zen at a time: the last one started serves
    except FileNotFoundError:
        pass
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    old = os.umask(0o177)
    try:
        server.bind(path)
    finally:
        os.umask(old)
    server.listen(8)
    ours = os.stat(path).st_ino
    bridge = Bridge(sys.stdout.buffer)

    def accept():
        while True:
            try:
                conn, _ = server.accept()
            except OSError:
                return
            threading.Thread(target=serve_client, args=(conn, bridge), daemon=True).start()

    threading.Thread(target=accept, daemon=True).start()
    try:
        read_messages(sys.stdin.buffer, bridge)
    finally:
        # Zen gone: the socket too (only when it is still ours).
        try:
            if os.stat(path).st_ino == ours:
                os.unlink(path)
        except OSError:
            pass
        server.close()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
