#!/usr/bin/env python3
"""nixbook-wayland-security-context: a restricted Wayland socket for a sandbox.

    nixbook-wayland-security-context SOCKET_PATH [APP_ID]

Asks the compositor of $WAYLAND_DISPLAY (wp_security_context_manager_v1,
security-context-v1: niri, sway, KDE…) to serve SOCKET_PATH as a sandbox's
socket: its clients are "restricted", refused the privileged protocols
(screen capture, virtual pointer and keyboard, the window list, layer
shell, session lock…), however they ask. The agent desktop's nested niri
reaches the user's desktop through it (scripts/agent-desktop.sh), so the
apps sandboxed with it can't capture or drive the user's screen.

The socket works until this exits, which it does when its standard input
closes (the launcher holds it) or on SIGTERM/SIGINT. Errors go to stderr,
exit 1: the caller must not fall back to the unrestricted socket.

Standard library only; the wire format as in desktop-mcp.py's VirtualPointer.
"""

import array
import os
import signal
import socket
import struct
import sys

MANAGER = "wp_security_context_manager_v1"
DISPLAY = 1


class Client:
    def __init__(self):
        name = os.environ.get("WAYLAND_DISPLAY") or "wayland-0"
        path = name if name.startswith("/") else os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "", name)
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(5)
        self.sock.connect(path)
        self.buf = b""
        self.next_id = 2
        self.globals = {}
        self.registry = self.new_id()
        self.send(DISPLAY, 1, self.u32(self.registry))  # wl_display.get_registry
        self.roundtrip()

    @staticmethod
    def u32(v):
        return struct.pack("<I", v & 0xFFFFFFFF)

    @staticmethod
    def string(v):
        data = v.encode() + b"\0"
        return struct.pack("<I", len(data)) + data + b"\0" * (-len(data) % 4)

    def new_id(self):
        i = self.next_id
        self.next_id += 1
        return i

    def send(self, obj_id, opcode, payload=b"", fds=()):
        size = 8 + len(payload)
        data = struct.pack("<II", obj_id, (size << 16) | opcode) + payload
        if fds:
            # File descriptor arguments travel out of band (SCM_RIGHTS).
            self.sock.sendmsg([data], [(socket.SOL_SOCKET, socket.SCM_RIGHTS, array.array("i", fds))])
        else:
            self.sock.sendall(data)

    def read_event(self):
        while len(self.buf) < 8 or len(self.buf) < (struct.unpack_from("<I", self.buf, 4)[0] >> 16):
            chunk = self.sock.recv(65536)
            if not chunk:
                raise RuntimeError("the compositor closed the connection")
            self.buf += chunk
        obj, word = struct.unpack_from("<II", self.buf)
        size, opcode = word >> 16, word & 0xFFFF
        body, self.buf = self.buf[8:size], self.buf[size:]
        return obj, opcode, body

    @staticmethod
    def read_string(body, off):
        n = struct.unpack_from("<I", body, off)[0]
        return body[off + 4 : off + 4 + n - 1].decode(errors="replace"), off + 4 + n + (-n % 4)

    def roundtrip(self):
        cb = self.new_id()
        self.send(DISPLAY, 0, self.u32(cb))  # wl_display.sync
        while True:
            obj, opcode, body = self.read_event()
            if obj == cb and opcode == 0:  # wl_callback.done
                return
            if obj == DISPLAY and opcode == 0:  # wl_display.error
                _, code = struct.unpack_from("<II", body)
                msg, _ = self.read_string(body, 8)
                raise RuntimeError(f"Wayland protocol error {code}: {msg}")
            if obj == self.registry and opcode == 0:  # wl_registry.global
                name = struct.unpack_from("<I", body)[0]
                iface, off = self.read_string(body, 4)
                self.globals.setdefault(iface, (name, struct.unpack_from("<I", body, off)[0]))

    def bind(self, iface, version):
        name, advertised = self.globals[iface]
        new = self.new_id()
        self.send(self.registry, 0, self.u32(name) + self.string(iface) + self.u32(min(version, advertised)) + self.u32(new))
        return new


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__.split("\n\n")[1])
    path = sys.argv[1]
    app_id = sys.argv[2] if len(sys.argv) == 3 else "nixbook-agent-desktop"
    try:
        client = Client()
        if MANAGER not in client.globals:
            raise RuntimeError(f"the compositor has no {MANAGER} (security-context-v1)")
        manager = client.bind(MANAGER, 1)

        listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        if os.path.lexists(path):
            os.unlink(path)
        listener.bind(path)
        listener.listen(16)
        # The compositor stops serving the socket once close_fd hangs up: the
        # read end goes to it, this keeps the write end until it exits.
        close_r, close_w = os.pipe()

        context = client.new_id()
        # create_listener(new_id, listen_fd, close_fd)
        client.send(manager, 1, client.u32(context), fds=(listener.fileno(), close_r))
        client.send(context, 1, client.string("nixbook"))  # set_sandbox_engine
        client.send(context, 2, client.string(app_id))  # set_app_id
        client.send(context, 3, client.string(str(os.getpid())))  # set_instance_id
        client.send(context, 4)  # commit
        client.roundtrip()  # a protocol error shows up here
        os.close(close_r)
        listener.close()
    except (OSError, RuntimeError) as e:
        print(f"nixbook-wayland-security-context: {e}", file=sys.stderr)
        sys.exit(1)

    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    signal.signal(signal.SIGINT, lambda *_: sys.exit(0))
    print("ready", flush=True)
    try:
        while sys.stdin.buffer.read(4096):
            pass
    finally:
        os.close(close_w)
        try:
            os.unlink(path)
        except OSError:
            pass


if __name__ == "__main__":
    main()
