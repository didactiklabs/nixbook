#!/usr/bin/env python3
"""A fake Zen (WebDriver BiDi) and Vesktop (Chrome DevTools Protocol) for
tests/desktop-mcp.sh: on 127.0.0.1:PORT, GET /json/list lists a Discord page,
and any WebSocket gets canned answers. Logs every command as a JSON line.

  fake-devtools.py PORT LOG
"""

import base64
import hashlib
import json
import socket
import struct
import sys
import threading

port, log_path = int(sys.argv[1]), sys.argv[2]
TABS = [{"context": "ctx-a", "url": "https://example.com/a?token=secret", "children": []},
        {"context": "ctx-b", "url": "https://example.org/b", "children": []}]


def log(entry):
    with open(log_path, "a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")


def value(v):
    if isinstance(v, bool):
        return {"type": "boolean", "value": v}
    if isinstance(v, str):
        return {"type": "string", "value": v}
    if isinstance(v, list):
        return {"type": "array", "value": [value(x) for x in v]}
    return {"type": "null"}


def call_function(params):
    fn, ctx = params["functionDeclaration"], params["target"]["context"]
    args = [a.get("value") for a in params.get("arguments", [])]
    if "document.title, document.visibilityState" in fn:
        return value(["Page " + ctx[-1].upper(), "visible" if ctx == "ctx-b" else "hidden"])
    if "document.visibilityState" in fn:
        return value("visible" if ctx == "ctx-b" else "hidden")
    if "document.title, location.href" in fn:
        return value(["Page B", "https://example.org/b"])
    if fn.strip() == "() => location.href":
        return value("https://example.org/b")
    if fn.strip() == "() => document.title":
        return value("Page B")
    if "innerText" in fn and "max" not in fn:
        return value("line one\nsecret line\nline three")
    if "(max, find, values)" in fn:
        return value(f"[1] link \"Next\"\n[2] text \"Query\" (filled) max={args[0]} values={str(args[2]).lower()}")
    if "scrollIntoView" in fn:
        return {"type": "node", "sharedId": f"node-{args[0]}"} if args[0] in (2, 3) else {"type": "null"}
    if ".type === 'password'" in fn:
        return value(args[0] == 3)
    return {"type": "undefined"}


def answer(msg):
    method, params = msg.get("method"), msg.get("params", {})
    if method == "Runtime.evaluate":
        expr = params["expression"]
        if "Vencord.Util.sendMessage" in expr:
            v = "Alesio [123]"
        elif "MessageStore.getMessages" in expr:
            v = ["# Alesio [123]", "10:00 Alesio: salut"]
        else:
            v = ["Alesio — unread 2"]
        return {"id": msg["id"], "result": {"result": {"type": "object", "value": v}}}
    result = {}
    if method == "session.new":
        result = {"sessionId": "s1"}
    elif method == "browsingContext.getTree":
        result = {"contexts": TABS}
    elif method == "browsingContext.create":
        result = {"context": "ctx-c"}
    elif method == "script.callFunction":
        result = {"type": "success", "realm": "r", "result": call_function(params)}
    return {"id": msg["id"], "type": "success", "result": result}


def recv_exact(conn, n, buf):
    while len(buf[0]) < n:
        chunk = conn.recv(65536)
        if not chunk:
            raise EOFError
        buf[0] += chunk
    out, buf[0] = buf[0][:n], buf[0][n:]
    return out


def send_text(conn, data):
    data = data.encode()
    n = len(data)
    head = bytes([0x81]) + (bytes([n]) if n < 126 else bytes([126]) + struct.pack(">H", n) if n < 65536
                            else bytes([127]) + struct.pack(">Q", n))
    conn.sendall(head + data)


def serve(conn):
    buf = [b""]
    try:
        while b"\r\n\r\n" not in buf[0]:
            buf[0] += conn.recv(65536)
        head, buf[0] = buf[0].split(b"\r\n\r\n", 1)
        lines = head.decode().split("\r\n")
        path = lines[0].split(" ")[1]
        headers = {k.lower(): v.strip() for k, v in (line.split(":", 1) for line in lines[1:] if ":" in line)}
        if "sec-websocket-key" not in headers:
            body = json.dumps([{"type": "page", "url": "https://discord.com/channels/@me",
                                "webSocketDebuggerUrl": f"ws://127.0.0.1:{port}/devtools/page/1"}]).encode()
            conn.sendall(b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: "
                         + str(len(body)).encode() + b"\r\nConnection: close\r\n\r\n" + body)
            return
        accept = base64.b64encode(hashlib.sha1((headers["sec-websocket-key"] +
                                                "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
        conn.sendall(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                      f"Sec-WebSocket-Accept: {accept}\r\n\r\n").encode())
        while True:
            b0, b1 = recv_exact(conn, 2, buf)
            n = b1 & 0x7F
            if n == 126:
                n = struct.unpack(">H", recv_exact(conn, 2, buf))[0]
            elif n == 127:
                n = struct.unpack(">Q", recv_exact(conn, 8, buf))[0]
            mask = recv_exact(conn, 4, buf) if b1 & 0x80 else b"\0\0\0\0"
            data = bytes(b ^ mask[i & 3] for i, b in enumerate(recv_exact(conn, n, buf)))
            if b0 & 0x0F == 8:
                return
            msg = json.loads(data)
            log({"path": path, "masked": bool(b1 & 0x80), **msg})
            send_text(conn, json.dumps(answer(msg)))
    except (EOFError, OSError):
        pass
    finally:
        conn.close()


srv = socket.socket()
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", port))
srv.listen()
print("ready", flush=True)
while True:
    c, _ = srv.accept()
    threading.Thread(target=serve, args=(c,), daemon=True).start()
