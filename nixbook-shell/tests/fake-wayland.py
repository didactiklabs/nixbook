#!/usr/bin/env python3
"""A fake Wayland compositor for tests/desktop-mcp.sh: advertises wl_seat and
zwlr_virtual_pointer_manager_v1, answers wl_display.sync, and logs every
request it decodes as a JSON line.

  fake-wayland.py SOCKET LOG [--no-virtual-pointer]
"""

import json
import os
import socket
import struct
import sys

sock_path, log_path = sys.argv[1], sys.argv[2]
with_vp = "--no-virtual-pointer" not in sys.argv

GLOBALS = [(1, "wl_seat", 7)] + ([(2, "zwlr_virtual_pointer_manager_v1", 2)] if with_vp else [])
POINTER_REQUESTS = {
    0: ("motion", "uff"),
    1: ("motion_absolute", "uuuuu"),
    2: ("button", "uuu"),
    3: ("axis", "uuf"),
    4: ("frame", ""),
    5: ("axis_source", "u"),
    6: ("axis_stop", "uu"),
    7: ("axis_discrete", "uufi"),
    8: ("destroy", ""),
}


def log(entry):
    with open(log_path, "a") as f:
        f.write(json.dumps(entry) + "\n")


def string(v):
    data = v.encode() + b"\0"
    return struct.pack("<I", len(data)) + data + b"\0" * (-len(data) % 4)


def event(obj, opcode, payload=b""):
    return struct.pack("<II", obj, ((8 + len(payload)) << 16) | opcode) + payload


def read_string(body, off):
    n = struct.unpack_from("<I", body, off)[0]
    return body[off + 4 : off + 4 + n - 1].decode(), off + 4 + n + (-n % 4)


def decode(fmt, body):
    out, off = [], 0
    for c in fmt:
        v = struct.unpack_from("<i" if c in "fi" else "<I", body, off)[0]
        out.append(v / 256 if c == "f" else v)
        off += 4
    return out


def serve(conn):
    objects = {1: "wl_display"}
    buf = b""
    while True:
        chunk = conn.recv(65536)
        if not chunk:
            return
        buf += chunk
        while len(buf) >= 8:
            obj, word = struct.unpack_from("<II", buf)
            size, opcode = word >> 16, word & 0xFFFF
            if len(buf) < size:
                break
            body, buf = buf[8:size], buf[size:]
            iface = objects.get(obj)
            if iface == "wl_display" and opcode == 0:  # sync
                cb = struct.unpack_from("<I", body)[0]
                conn.sendall(event(cb, 0, struct.pack("<I", 1)))
            elif iface == "wl_display" and opcode == 1:  # get_registry
                reg = struct.unpack_from("<I", body)[0]
                objects[reg] = "wl_registry"
                for name, gi, ver in GLOBALS:
                    conn.sendall(event(reg, 0, struct.pack("<I", name) + string(gi) + struct.pack("<I", ver)))
            elif iface == "wl_registry" and opcode == 0:  # bind
                name = struct.unpack_from("<I", body)[0]
                gi, off = read_string(body, 4)
                ver, new = struct.unpack_from("<II", body, off)
                objects[new] = gi
                log({"request": "bind", "interface": gi, "version": ver})
                if gi == "wl_seat":
                    conn.sendall(event(new, 0, struct.pack("<I", 3)))  # capabilities
            elif iface == "zwlr_virtual_pointer_manager_v1":
                if opcode == 0:
                    seat, new = struct.unpack_from("<II", body)
                    objects[new] = "zwlr_virtual_pointer_v1"
                    log({"request": "create_virtual_pointer", "seat": objects.get(seat)})
                else:
                    log({"request": "manager_destroy" if opcode == 1 else f"manager_{opcode}"})
            elif iface == "zwlr_virtual_pointer_v1":
                name, fmt = POINTER_REQUESTS[opcode]
                args = decode(fmt, body)
                if name not in ("motion", "motion_absolute", "button", "axis", "axis_stop", "axis_discrete"):
                    log({"request": name, "args": args})
                else:
                    log({"request": name, "args": args[1:]})  # without the timestamp
            else:
                log({"request": "unknown", "object": obj, "opcode": opcode})


def main():
    try:
        os.unlink(sock_path)
    except FileNotFoundError:
        pass
    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(sock_path)
    srv.listen(4)
    while True:
        conn, _ = srv.accept()
        with conn:
            try:
                serve(conn)
            except (OSError, struct.error):
                pass


main()
