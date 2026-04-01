#!/usr/bin/env python3
"""Discord IPC bridge for DankMaterialShell Discord Voice plugin.

Connects to Discord's local Unix socket IPC, handles authentication,
subscribes to voice events, and exposes state + controls via a JSON-lines
Unix socket that the QML plugin connects to with DankSocket.

Dependencies: Python 3.10+ stdlib only.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import signal
import struct
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

logging.basicConfig(
    level=logging.INFO,
    format="[discord-bridge] %(levelname)s: %(message)s",
    stream=sys.stderr,
)
log = logging.getLogger("discord-bridge")

# Discord StreamKit public client ID (no secret needed).
DEFAULT_CLIENT_ID = "207646673902501888"
OAUTH_SCOPES = ["rpc", "rpc.voice.read", "rpc.voice.write"]
TOKEN_EXCHANGE_URL = "https://streamkit.discord.com/overlay/token"

# Discord IPC opcodes.
OP_HANDSHAKE = 0
OP_FRAME = 1
OP_CLOSE = 2
OP_PING = 3
OP_PONG = 4


# ---------------------------------------------------------------------------
# Discord IPC (binary-framed Unix socket)
# ---------------------------------------------------------------------------

class DiscordIPC:
    """Low-level binary-framed communication with Discord's local IPC."""

    def __init__(self) -> None:
        self.reader: asyncio.StreamReader | None = None
        self.writer: asyncio.StreamWriter | None = None
        self._nonce: int = 0

    # -- connection --

    @staticmethod
    def _candidate_paths() -> list[str]:
        """Return candidate Discord IPC socket paths in priority order."""
        paths: list[str] = []
        env_dirs: list[str] = []

        if xdg := os.environ.get("XDG_RUNTIME_DIR"):
            env_dirs.append(xdg)
            # Flatpak
            flatpak = os.path.join(xdg, "app", "com.discordapp.Discord")
            if os.path.isdir(flatpak):
                env_dirs.append(flatpak)

        if snap := os.environ.get("SNAP_USER_DATA"):
            env_dirs.append(os.path.join(snap, ".config"))

        for var in ("TMPDIR", "TMP", "TEMP"):
            if d := os.environ.get(var):
                env_dirs.append(d)

        env_dirs.append("/tmp")

        for d in env_dirs:
            for i in range(10):
                paths.append(os.path.join(d, f"discord-ipc-{i}"))

        return paths

    async def connect(self) -> bool:
        """Try to connect to Discord's IPC socket.  Returns True on success."""
        for path in self._candidate_paths():
            if not os.path.exists(path):
                continue
            try:
                r, w = await asyncio.open_unix_connection(path)
                self.reader, self.writer = r, w
                log.info("Connected to Discord IPC at %s", path)
                return True
            except (OSError, ConnectionRefusedError):
                continue
        return False

    def close(self) -> None:
        if self.writer:
            try:
                self.writer.close()
            except Exception:
                pass
            self.writer = None
            self.reader = None

    @property
    def connected(self) -> bool:
        return self.writer is not None and not self.writer.is_closing()

    # -- framing --

    async def send_frame(self, opcode: int, payload: dict[str, Any]) -> None:
        """Send a binary-framed message to Discord."""
        data = json.dumps(payload).encode("utf-8")
        header = struct.pack("<II", opcode, len(data))
        assert self.writer is not None
        self.writer.write(header + data)
        await self.writer.drain()

    async def recv_frame(self) -> tuple[int, dict[str, Any]]:
        """Receive a binary-framed message from Discord."""
        assert self.reader is not None
        header = await self.reader.readexactly(8)
        opcode, length = struct.unpack("<II", header)
        data = await self.reader.readexactly(length)
        payload = json.loads(data.decode("utf-8"))
        return opcode, payload

    # -- protocol helpers --

    def _next_nonce(self) -> str:
        self._nonce += 1
        return str(self._nonce)

    async def handshake(self, client_id: str) -> dict[str, Any]:
        """Send HANDSHAKE, return the READY payload."""
        await self.send_frame(OP_HANDSHAKE, {"v": 1, "client_id": client_id})
        op, data = await asyncio.wait_for(self.recv_frame(), timeout=5)
        if op == OP_CLOSE:
            raise ConnectionError(f"Discord closed connection: {data}")
        if data.get("evt") != "READY":
            raise ConnectionError(f"Expected READY, got: {data}")
        return data

    async def authorize(self, client_id: str, scopes: list[str]) -> str:
        """AUTHORIZE -> returns OAuth code.  Discord shows consent UI."""
        nonce = self._next_nonce()
        await self.send_frame(OP_FRAME, {
            "cmd": "AUTHORIZE",
            "args": {
                "client_id": client_id,
                "scopes": scopes,
                "prompt": "consent",
            },
            "nonce": nonce,
        })
        return nonce

    async def authenticate(self, access_token: str) -> str:
        """AUTHENTICATE with an access token.  Returns nonce."""
        nonce = self._next_nonce()
        await self.send_frame(OP_FRAME, {
            "cmd": "AUTHENTICATE",
            "args": {"access_token": access_token},
            "nonce": nonce,
        })
        return nonce

    async def subscribe(self, evt: str, args: dict[str, Any] | None = None) -> str:
        """SUBSCRIBE to a Discord event.  Returns nonce."""
        nonce = self._next_nonce()
        payload: dict[str, Any] = {"cmd": "SUBSCRIBE", "evt": evt, "nonce": nonce}
        if args:
            payload["args"] = args
        await self.send_frame(OP_FRAME, payload)
        return nonce

    async def unsubscribe(self, evt: str, args: dict[str, Any] | None = None) -> str:
        """UNSUBSCRIBE from a Discord event.  Returns nonce."""
        nonce = self._next_nonce()
        payload: dict[str, Any] = {"cmd": "UNSUBSCRIBE", "evt": evt, "nonce": nonce}
        if args:
            payload["args"] = args
        await self.send_frame(OP_FRAME, payload)
        return nonce


# ---------------------------------------------------------------------------
# Token management
# ---------------------------------------------------------------------------

class TokenManager:
    """OAuth token caching and exchange via StreamKit endpoint."""

    def __init__(self, cache_dir: str | None = None) -> None:
        if cache_dir is None:
            xdg_cache = os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache"))
            cache_dir = os.path.join(xdg_cache, "DankMaterialShell")
        self._cache_path = os.path.join(cache_dir, "discord_token.json")
        self.access_token: str | None = None

    def load(self) -> str | None:
        """Load cached access token from disk."""
        try:
            with open(self._cache_path) as f:
                data = json.load(f)
                self.access_token = data.get("access_token")
                return self.access_token
        except (FileNotFoundError, json.JSONDecodeError, KeyError):
            return None

    def save(self, token: str) -> None:
        """Save access token to disk."""
        self.access_token = token
        os.makedirs(os.path.dirname(self._cache_path), exist_ok=True)
        with open(self._cache_path, "w") as f:
            json.dump({"access_token": token}, f)

    def clear(self) -> None:
        """Remove cached token."""
        self.access_token = None
        try:
            os.unlink(self._cache_path)
        except FileNotFoundError:
            pass

    @staticmethod
    def exchange_code(code: str) -> str:
        """Exchange OAuth code for access token via StreamKit endpoint."""
        body = json.dumps({"code": code}).encode("utf-8")
        req = urllib.request.Request(
            TOKEN_EXCHANGE_URL,
            data=body,
            headers={
                "Content-Type": "application/json",
                "User-Agent": "DankMaterialShell/1.0",
            },
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return data["access_token"]


# ---------------------------------------------------------------------------
# Vesktop token discovery
# ---------------------------------------------------------------------------

import http.server
import threading
import webbrowser


class _OAuth2CallbackHandler(http.server.BaseHTTPRequestHandler):
    """HTTP handler that serves the OAuth2 callback page and captures the token."""

    token_result: str | None = None
    token_event: threading.Event = threading.Event()

    def do_GET(self) -> None:
        if self.path.startswith("/callback"):
            # Serve the callback HTML that extracts the token from the URL fragment
            html = b"""<!DOCTYPE html>
<html><head><title>Discord Auth</title></head>
<body>
<p>Authenticating with Discord...</p>
<script>
(function() {
    var hash = window.location.hash.substring(1);
    var params = new URLSearchParams(hash);
    var token = params.get('access_token');
    if (token) {
        fetch('/token', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({access_token: token})
        }).then(function() {
            document.body.innerHTML = '<p style="color:green;font-size:24px;">Authenticated! You can close this tab.</p>';
        });
    } else {
        document.body.innerHTML = '<p style="color:red;font-size:24px;">No token found. Error: ' + (params.get('error') || 'unknown') + '</p>';
    }
})();
</script>
</body></html>"""
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.end_headers()
            self.wfile.write(html)
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self) -> None:
        if self.path == "/token":
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length)
            try:
                data = json.loads(body)
                token = data.get("access_token", "")
                if token:
                    _OAuth2CallbackHandler.token_result = token
                    _OAuth2CallbackHandler.token_event.set()
            except (json.JSONDecodeError, KeyError):
                pass
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"ok":true}')
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format: str, *args: Any) -> None:
        pass  # Suppress HTTP server logs


def _oauth2_login(client_id: str = DEFAULT_CLIENT_ID, port: int = 6477) -> str | None:
    """Run a local OAuth2 flow to get a Discord token.

    Opens the browser for the user to authorize, then captures the token
    from the redirect.
    """
    _OAuth2CallbackHandler.token_result = None
    _OAuth2CallbackHandler.token_event.clear()

    redirect_uri = f"http://localhost:{port}/callback"
    scopes = "rpc rpc.voice.read rpc.voice.write"
    params = urllib.parse.urlencode({
        "client_id": client_id,
        "response_type": "token",
        "redirect_uri": redirect_uri,
        "scope": scopes,
    })
    auth_url = f"https://discord.com/oauth2/authorize?{params}"

    # Start local HTTP server
    try:
        server = http.server.HTTPServer(("127.0.0.1", port), _OAuth2CallbackHandler)
        server.timeout = 1
    except OSError as e:
        log.error("Cannot start OAuth2 server on port %d: %s", port, e)
        return None

    log.info("Opening Discord OAuth2 login in browser...")
    webbrowser.open(auth_url)

    # Process requests until token received or timeout
    import time
    start = time.monotonic()
    while time.monotonic() - start < 120:
        if _OAuth2CallbackHandler.token_event.is_set():
            break
        server.handle_request()  # handles one request at a time

    server.server_close()

    if _OAuth2CallbackHandler.token_result:
        log.info("OAuth2 token received")
        return _OAuth2CallbackHandler.token_result

    log.warning("OAuth2 login timed out or failed")
    return None


def _find_vesktop_token() -> str | None:
    """Try to find Discord token for Vesktop/Gateway mode.

    Checks:
    1. DISCORD_TOKEN environment variable
    2. ~/.config/DankMaterialShell/discord_token file
    """
    # 1. Environment variable
    if token := os.environ.get("DISCORD_TOKEN"):
        return token.strip()

    # 2. Config file
    xdg_config = os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config"))
    token_file = os.path.join(xdg_config, "DankMaterialShell", "discord_token")
    try:
        with open(token_file) as f:
            token = f.read().strip()
            if token:
                return token
    except FileNotFoundError:
        pass

    return None


# ---------------------------------------------------------------------------
# Discord Gateway (WebSocket for Vesktop/arRPC voice state)
# ---------------------------------------------------------------------------

import base64
import hashlib
import os as _os
import socket as _socket
import ssl as _ssl
import struct as _struct
import secrets


class DiscordGateway:
    """Minimal Discord Gateway WebSocket client for voice state monitoring.

    Connects to Discord's Gateway, authenticates with a user token,
    and receives VOICE_STATE_UPDATE events. Uses only stdlib.
    """

    GATEWAY_URL = "gateway.discord.gg"
    GATEWAY_PORT = 443
    GATEWAY_PATH = "/?v=10&encoding=json"

    # WebSocket opcodes
    WS_OP_CONTINUATION = 0x0
    WS_OP_TEXT = 0x1
    WS_OP_BINARY = 0x2
    WS_OP_CLOSE = 0x8
    WS_OP_PING = 0x9
    WS_OP_PONG = 0xA

    # Discord Gateway opcodes
    DISPATCH = 0
    HEARTBEAT = 1
    IDENTIFY = 2
    RESUME = 6
    REQUEST_GUILD_MEMBERS = 8
    INVALID_SESSION = 9
    HELLO = 10
    HEARTBEAT_ACK = 11

    def __init__(self, token: str) -> None:
        self.token = token
        self._sock: _ssl.SSLSocket | None = None
        self._session_id: str | None = None
        self._resume_url: str | None = None
        self._heartbeat_interval: float = 41.25
        self._last_sequence: int | None = None
        self._heartbeat_task: asyncio.Task[None] | None = None
        self._read_buffer: bytes = b""
        self._on_voice_state: Any = None
        self._on_ready: Any = None
        self._user: dict[str, Any] = {}
        self._shutdown = False

    @property
    def connected(self) -> bool:
        return self._sock is not None

    @property
    def user(self) -> dict[str, Any]:
        return self._user

    def set_callbacks(self, on_voice_state: Any = None, on_ready: Any = None) -> None:
        self._on_voice_state = on_voice_state
        self._on_ready = on_ready

    async def connect(self) -> bool:
        """Connect to Discord Gateway via WebSocket. Returns True on success."""
        try:
            # Create SSL socket
            ctx = _ssl.create_default_context()
            raw_sock = _socket.create_connection(
                (self.GATEWAY_URL, self.GATEWAY_PORT), timeout=10
            )
            self._sock = ctx.wrap_socket(raw_sock, server_hostname=self.GATEWAY_URL)
            self._sock.setblocking(False)

            # WebSocket handshake
            key = base64.b64encode(secrets.token_bytes(16)).decode()
            handshake = (
                f"GET {self.GATEWAY_PATH} HTTP/1.1\r\n"
                f"Host: {self.GATEWAY_URL}\r\n"
                f"Upgrade: websocket\r\n"
                f"Connection: Upgrade\r\n"
                f"Sec-WebSocket-Key: {key}\r\n"
                f"Sec-WebSocket-Version: 13\r\n"
                f"\r\n"
            )
            await asyncio.get_event_loop().sock_sendall(self._sock, handshake.encode())

            # Read handshake response
            response = b""
            while b"\r\n\r\n" not in response:
                chunk = await asyncio.get_event_loop().sock_recv(self._sock, 4096)
                if not chunk:
                    return False
                response += chunk

            if b"101" not in response.split(b"\r\n")[0]:
                log.error("WebSocket handshake failed: %s", response[:200])
                return False

            log.info("Connected to Discord Gateway")
            return True

        except Exception as e:
            log.error("Gateway connection failed: %s", e)
            if self._sock:
                try:
                    self._sock.close()
                except Exception:
                    pass
                self._sock = None
            return False

    def close(self) -> None:
        """Close the Gateway connection."""
        self._shutdown = True
        if self._heartbeat_task:
            self._heartbeat_task.cancel()
        if self._sock:
            try:
                self._send_ws_frame(_struct.pack("!HH", 1000, 0), self.WS_OP_CLOSE)
            except Exception:
                pass
            try:
                self._sock.close()
            except Exception:
                pass
            self._sock = None

    # -- WebSocket framing --

    def _send_ws_frame(self, payload: bytes, opcode: int = 1) -> None:
        """Send a WebSocket frame."""
        if not self._sock:
            return
        frame = bytearray()
        frame.append(0x80 | opcode)  # FIN + opcode

        length = len(payload)
        if length < 126:
            frame.append(0x80 | length)  # MASK + length
        elif length < 65536:
            frame.append(0x80 | 126)
            frame.extend(_struct.pack("!H", length))
        else:
            frame.append(0x80 | 127)
            frame.extend(_struct.pack("!Q", length))

        # Generate mask key
        mask_key = _os.urandom(4)
        frame.extend(mask_key)

        # Mask payload
        masked = bytearray(length)
        for i in range(length):
            masked[i] = payload[i] ^ mask_key[i % 4]
        frame.extend(masked)

        self._sock.sendall(bytes(frame))

    async def _recv_ws_frame(self) -> tuple[int, bytes]:
        """Receive a WebSocket frame. Returns (opcode, payload)."""
        if not self._sock:
            raise ConnectionError("Not connected")
        loop = asyncio.get_event_loop()

        async def read_exact(n: int) -> bytes:
            data = b""
            while len(data) < n:
                assert self._sock is not None
                chunk = await loop.sock_recv(self._sock, n - len(data))
                if not chunk:
                    raise ConnectionError("Connection closed")
                data += chunk
            return data

        header = await read_exact(2)
        byte1, byte2 = header[0], header[1]
        opcode = byte1 & 0x0F
        masked = bool(byte2 & 0x80)
        length = byte2 & 0x7F

        if length == 126:
            length = _struct.unpack("!H", await read_exact(2))[0]
        elif length == 127:
            length = _struct.unpack("!Q", await read_exact(8))[0]

        if masked:
            mask_key = await read_exact(4)
            payload = await read_exact(length)
            payload = bytearray(payload)
            for i in range(length):
                payload[i] ^= mask_key[i % 4]
            payload = bytes(payload)
        else:
            payload = await read_exact(length)

        return opcode, payload

    async def _send_discord(self, op: int, data: Any) -> None:
        """Send a Discord Gateway payload."""
        payload = json.dumps({"op": op, "d": data}).encode()
        self._send_ws_frame(payload, 1)

    async def _heartbeat_loop(self) -> None:
        """Send heartbeats at the required interval."""
        try:
            while not self._shutdown:
                await asyncio.sleep(self._heartbeat_interval)
                if self._shutdown:
                    break
                seq = self._last_sequence
                await self._send_discord(self.HEARTBEAT, seq)
                log.debug("Gateway heartbeat sent (seq=%s)", seq)
        except asyncio.CancelledError:
            pass
        except Exception as e:
            log.error("Heartbeat error: %s", e)

    async def identify(self) -> bool:
        """Send IDENTIFY to authenticate with the Gateway."""
        try:
            await self._send_discord(self.IDENTIFY, {
                "token": self.token,
                "properties": {
                    "os": "linux",
                    "browser": "DMS-Discord-Voice",
                    "device": "DMS-Discord-Voice",
                },
                "intents": (1 << 0) | (1 << 1) | (1 << 7),  # GUILDS, GUILD_MEMBERS, GUILD_VOICE_STATES
            })
            return True
        except Exception as e:
            log.error("Identify failed: %s", e)
            return False

    async def run(self) -> None:
        """Main Gateway event loop. Call after connect()."""
        try:
            while not self._shutdown:
                opcode, payload = await asyncio.wait_for(
                    self._recv_ws_frame(), timeout=60
                )

                if opcode == self.WS_OP_CLOSE:
                    log.warning("Gateway closed connection")
                    break
                elif opcode == self.WS_OP_PING:
                    self._send_ws_frame(payload, self.WS_OP_PONG)
                    continue
                elif opcode not in (self.WS_OP_TEXT, self.WS_OP_BINARY):
                    continue

                try:
                    msg = json.loads(payload.decode("utf-8"))
                except (json.JSONDecodeError, UnicodeDecodeError):
                    continue

                await self._handle_message(msg)

        except asyncio.TimeoutError:
            log.warning("Gateway read timeout")
        except ConnectionError as e:
            log.warning("Gateway connection lost: %s", e)
        except Exception as e:
            log.error("Gateway error: %s", e)
        finally:
            self.close()

    async def _handle_message(self, msg: dict[str, Any]) -> None:
        """Handle a Gateway message."""
        op = msg.get("op")
        d: dict[str, Any] = msg.get("d") or {}
        t = msg.get("t")
        s = msg.get("s")

        if s is not None:
            self._last_sequence = s

        if op == self.DISPATCH:
            if t == "READY":
                self._session_id = d.get("session_id")
                self._resume_url = d.get("resume_gateway_url")
                self._user = d.get("user", {})
                log.info("Gateway READY as %s", self._user.get("username", "?"))
                if self._on_ready:
                    await self._on_ready(d)

            elif t == "VOICE_STATE_UPDATE":
                if self._on_voice_state:
                    await self._on_voice_state(d)

        elif op == self.HELLO:
            self._heartbeat_interval = d.get("heartbeat_interval", 41250) / 1000.0
            self._heartbeat_task = asyncio.ensure_future(self._heartbeat_loop())
            await self.identify()

        elif op == self.HEARTBEAT_ACK:
            pass  # heartbeat acknowledged

        elif op == self.INVALID_SESSION:
            log.warning("Gateway invalid session, will re-identify")
            await asyncio.sleep(5)
            await self.identify()

        elif op == self.HEARTBEAT:
            seq = self._last_sequence if self._last_sequence is not None else None
            await self._send_discord(self.HEARTBEAT, seq)


# ---------------------------------------------------------------------------
# Bridge server (JSON-lines over Unix socket for QML DankSocket)
# ---------------------------------------------------------------------------

class BridgeServer:
    """Unix socket server that speaks JSON-lines to QML plugin instances.

    Supports multiple concurrent clients (one per monitor/widget instance).
    Broadcasts state to all, accepts commands from any.
    """

    def __init__(self, socket_path: str) -> None:
        self.socket_path = socket_path
        self._server: asyncio.AbstractServer | None = None
        self._clients: set[asyncio.StreamWriter] = set()
        self._on_command: Any = None  # callback: async (dict) -> None

    async def start(self, on_command: Any) -> None:
        self._on_command = on_command
        # Remove stale socket file with retry for EADDRINUSE.
        for attempt in range(5):
            try:
                os.unlink(self.socket_path)
            except FileNotFoundError:
                pass
            try:
                self._server = await asyncio.start_unix_server(
                    self._handle_client, path=self.socket_path
                )
                try:
                    os.chmod(self.socket_path, 0o600)
                except FileNotFoundError:
                    pass
                log.info("Bridge server listening on %s", self.socket_path)
                return
            except OSError as e:
                if e.errno == 98 and attempt < 4:  # EADDRINUSE
                    log.warning("Socket %s busy, retrying in 1s (attempt %d/5)...", self.socket_path, attempt + 1)
                    await asyncio.sleep(1)
                else:
                    raise

    async def _handle_client(
        self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ) -> None:
        self._clients.add(writer)
        log.info("QML client connected (total: %d)", len(self._clients))
        await self._send_one(writer, {"type": "ready"})

        try:
            while True:
                line = await reader.readline()
                if not line:
                    break
                try:
                    msg = json.loads(line.decode("utf-8").strip())
                    if self._on_command:
                        await self._on_command(msg)
                except json.JSONDecodeError:
                    log.warning("Bad JSON from QML: %s", line[:200])
        except (ConnectionResetError, asyncio.IncompleteReadError):
            pass
        finally:
            self._clients.discard(writer)
            try:
                writer.close()
            except Exception:
                pass
            log.info("QML client disconnected (total: %d)", len(self._clients))

    async def _send_one(self, writer: asyncio.StreamWriter, msg: dict[str, Any]) -> None:
        """Send a JSON-line message to a single client."""
        try:
            data = json.dumps(msg, separators=(",", ":")) + "\n"
            writer.write(data.encode("utf-8"))
            await writer.drain()
        except (ConnectionResetError, BrokenPipeError, ConnectionAbortedError):
            self._clients.discard(writer)

    async def send(self, msg: dict[str, Any]) -> None:
        """Broadcast a JSON-line message to all connected clients."""
        dead: list[asyncio.StreamWriter] = []
        data = json.dumps(msg, separators=(",", ":")) + "\n"
        encoded = data.encode("utf-8")
        for writer in list(self._clients):
            if writer.is_closing():
                dead.append(writer)
                continue
            try:
                writer.write(encoded)
                await writer.drain()
            except (ConnectionResetError, BrokenPipeError, ConnectionAbortedError):
                dead.append(writer)
        for w in dead:
            self._clients.discard(w)

    @property
    def has_client(self) -> bool:
        return len(self._clients) > 0

    async def stop(self) -> None:
        for writer in list(self._clients):
            try:
                writer.close()
            except Exception:
                pass
        self._clients.clear()
        if self._server:
            self._server.close()
            await self._server.wait_closed()
        try:
            os.unlink(self.socket_path)
        except FileNotFoundError:
            pass


# ---------------------------------------------------------------------------
# Main bridge coordinator
# ---------------------------------------------------------------------------

class DiscordBridge:
    """Coordinates Discord IPC, token management, and the QML bridge server."""

    def __init__(self, socket_path: str, client_id: str = DEFAULT_CLIENT_ID) -> None:
        self.client_id = client_id
        self.discord = DiscordIPC()
        self.tokens = TokenManager()
        self.server = BridgeServer(socket_path)
        self.authenticated = False
        self.current_channel_id: str | None = None
        self.voice_users: dict[str, dict[str, Any]] = {}
        self._pending: dict[str, str] = {}  # nonce -> command name
        self._shutdown = False
        self._discord_task: asyncio.Task[None] | None = None
        self._gateway: DiscordGateway | None = None
        self._gateway_mode = False
        self._my_user_id: str | None = None

    # -- main entry --

    async def run(self) -> None:
        loop = asyncio.get_running_loop()
        for sig in (signal.SIGTERM, signal.SIGINT):
            loop.add_signal_handler(sig, lambda: asyncio.ensure_future(self.shutdown()))

        await self.server.start(self._handle_qml_command)
        log.info("Bridge running, waiting for QML client...")

        # Auto-connect to Discord when IPC socket appears.
        asyncio.ensure_future(self._auto_connect_loop())

        # Keep running until shutdown.
        while not self._shutdown:
            await asyncio.sleep(1)

    async def _auto_connect_loop(self) -> None:
        """Background loop: connect to Discord as soon as its IPC socket appears."""
        retry_delays = [5, 10, 30, 60]
        attempt = 0
        while not self._shutdown:
            if self.discord.connected or self._gateway_mode:
                await asyncio.sleep(5)
                continue
            if await self._connect_discord(notify_qml=True):
                if self._gateway_mode:
                    # Gateway mode - connection handled by _start_gateway
                    return
                self._discord_task = asyncio.create_task(self._discord_read_loop())
                token = self.tokens.load()
                if token:
                    nonce = await self.discord.authenticate(token)
                    self._pending[nonce] = "AUTHENTICATE"
                else:
                    await self.server.send({"type": "auth_required"})
                return
            delay = retry_delays[min(attempt, len(retry_delays) - 1)]
            if attempt == 0:
                log.info("Discord IPC not found, polling every %ds...", delay)
            attempt += 1
            await asyncio.sleep(delay)

    async def shutdown(self) -> None:
        log.info("Shutting down...")
        self._shutdown = True
        self.discord.close()
        if self._gateway:
            self._gateway.close()
        await self.server.stop()

    # -- Discord connection --

    async def _connect_discord(self, notify_qml: bool = True) -> bool:
        """Connect and handshake with Discord.  Returns True on success."""
        if not await self.discord.connect():
            if notify_qml:
                await self.server.send({"type": "error", "error": "Discord not running or IPC unavailable"})
            return False
        try:
            ready = await self.discord.handshake(self.client_id)
            # Detect arRPC which only handles handshakes, not full RPC.
            user = ready.get("data", {}).get("user", {})
            if user.get("username") == "arrpc":
                log.info("Detected arRPC - trying Gateway mode")
                self.discord.close()
                # Try Gateway mode with user token
                token = _find_vesktop_token()
                if token:
                    asyncio.ensure_future(self._start_gateway(token))
                    return True  # Let auto-connect loop proceed
                if notify_qml:
                    await self.server.send({
                        "type": "auth_error",
                        "error": "Vesktop detected - click Login to connect",
                    })
                return False
            log.info("Discord handshake complete")
            return True
        except asyncio.TimeoutError:
            log.warning("Discord handshake timed out")
            self.discord.close()
            if notify_qml:
                await self.server.send({"type": "auth_error", "error": "Discord handshake timed out"})
            return False
        except Exception as e:
            log.warning("Handshake failed: %s", e)
            self.discord.close()
            if notify_qml:
                await self.server.send({"type": "error", "error": f"Handshake failed: {e}"})
            return False

    # -- Gateway (Vesktop) mode --

    async def _start_gateway(self, token: str) -> None:
        """Start Discord Gateway connection for Vesktop voice monitoring."""
        log.info("Starting Discord Gateway connection...")
        self._gateway = DiscordGateway(token)
        self._gateway.set_callbacks(
            on_voice_state=self._on_gateway_voice_state,
            on_ready=self._on_gateway_ready,
        )
        try:
            if await self._gateway.connect():
                self._gateway_mode = True
                await self._gateway.run()
        except Exception as e:
            log.error("Gateway error: %s", e)
        finally:
            self._gateway_mode = False
            self._gateway = None
            self.authenticated = False
            self.current_channel_id = None
            self.voice_users.clear()
            await self.server.send({"type": "disconnected", "reason": "Gateway disconnected"})

    async def _on_gateway_ready(self, data: dict[str, Any]) -> None:
        """Handle Gateway READY event."""
        user = data.get("user", {})
        self._my_user_id = user.get("id")
        self.authenticated = True
        log.info("Gateway ready as user %s (id=%s)", user.get("username", "?"), self._my_user_id)
        await self.server.send({
            "type": "auth_complete",
            "user": {
                "id": user.get("id", ""),
                "username": user.get("username", ""),
                "avatar": user.get("avatar", ""),
            },
            "access_token": "",
        })

    async def _on_gateway_voice_state(self, data: dict[str, Any]) -> None:
        """Handle VOICE_STATE_UPDATE from Gateway."""
        user = data.get("user", {})
        uid = user.get("id", "")
        channel_id = data.get("channel_id")
        guild_id = data.get("guild_id", "")

        if uid == self._my_user_id:
            # Our own voice state changed
            if channel_id and channel_id != self.current_channel_id:
                # We joined a new channel
                self.current_channel_id = channel_id
                self.voice_users.clear()
                self.authenticated = True
                await self.server.send({
                    "type": "voice_channel",
                    "channel": {
                        "id": channel_id,
                        "name": data.get("guild_id", "Voice Channel"),
                        "guild_id": guild_id,
                    },
                })
                log.info("Gateway: joined voice channel %s", channel_id)
            elif not channel_id and self.current_channel_id:
                # We left the channel
                self.current_channel_id = None
                self.voice_users.clear()
                await self.server.send({"type": "voice_channel", "channel": None})
                log.info("Gateway: left voice channel")
        elif self.current_channel_id:
            # Another user's voice state changed
            if channel_id == self.current_channel_id:
                # User joined/updated in our channel
                self.voice_users[uid] = {
                    "id": uid,
                    "username": user.get("username", ""),
                    "avatar": user.get("avatar", ""),
                    "nick": data.get("nick", "") or user.get("username", ""),
                    "mute": data.get("mute", False),
                    "self_mute": data.get("self_mute", False),
                    "deaf": data.get("deaf", False),
                    "self_deaf": data.get("self_deaf", False),
                    "speaking": False,
                }
                await self.server.send({
                    "type": "voice_state",
                    "users": list(self.voice_users.values()),
                })
            elif uid in self.voice_users:
                # User left our channel
                del self.voice_users[uid]
                await self.server.send({
                    "type": "voice_state",
                    "users": list(self.voice_users.values()),
                })

    async def _discord_read_loop(self) -> None:
        """Read frames from Discord and dispatch events."""
        try:
            while self.discord.connected and not self._shutdown:
                try:
                    op, data = await asyncio.wait_for(
                        self.discord.recv_frame(), timeout=10
                    )
                except asyncio.TimeoutError:
                    # No data from Discord - connection may be dead or
                    # we're connected to arRPC which only handles handshakes.
                    continue
                except asyncio.IncompleteReadError:
                    break
                except Exception as e:
                    log.error("Discord read error: %s", e)
                    break

                if op == OP_CLOSE:
                    log.warning("Discord closed connection: %s", data)
                    break
                elif op == OP_PING:
                    await self.discord.send_frame(OP_PONG, data)
                    continue
                elif op == OP_PONG:
                    continue

                # OP_FRAME: could be a command response or a dispatched event.
                await self._handle_discord_message(data)
        except Exception as e:
            log.error("Discord read loop error: %s", e)
        finally:
            self.discord.close()
            self.authenticated = False
            self.current_channel_id = None
            self.voice_users.clear()
            await self.server.send({"type": "disconnected", "reason": "Discord connection lost"})
            log.info("Discord disconnected, will retry on next connect command")

    async def _handle_discord_message(self, data: dict[str, Any]) -> None:
        """Handle a single message from Discord (response or dispatch)."""
        nonce = data.get("nonce")
        cmd = data.get("cmd", "")
        evt = data.get("evt")

        # Check for errors.
        if evt == "ERROR":
            error_data = data.get("data", {})
            log.error("Discord error: %s", error_data.get("message", data))
            await self.server.send({"type": "error", "error": error_data.get("message", "Unknown error")})
            return

        # Command responses (have nonce).
        if nonce and nonce in self._pending:
            pending_cmd = self._pending.pop(nonce)
            await self._handle_command_response(pending_cmd, data)
            return

        # Dispatched events (evt field, cmd == "DISPATCH").
        if cmd == "DISPATCH" and evt:
            await self._handle_dispatch(evt, data.get("data", {}))

    async def _handle_command_response(self, cmd_name: str, data: dict[str, Any]) -> None:
        """Handle a response to a command we sent."""
        response_data = data.get("data", {})

        if cmd_name == "AUTHORIZE":
            code = response_data.get("code")
            if not code:
                await self.server.send({"type": "auth_error", "error": "Authorization denied or failed"})
                return
            # Exchange code for token.
            try:
                token = await asyncio.get_running_loop().run_in_executor(
                    None, TokenManager.exchange_code, code
                )
                self.tokens.save(token)
                # Now authenticate with the token.
                nonce = await self.discord.authenticate(token)
                self._pending[nonce] = "AUTHENTICATE"
            except Exception as e:
                log.error("Token exchange failed: %s", e)
                await self.server.send({"type": "auth_error", "error": f"Token exchange failed: {e}"})

        elif cmd_name == "AUTHENTICATE":
            user = response_data.get("user", {})
            self.authenticated = True
            token = self.tokens.access_token or ""
            await self.server.send({
                "type": "auth_complete",
                "user": {
                    "id": user.get("id", ""),
                    "username": user.get("username", ""),
                    "avatar": user.get("avatar", ""),
                },
                "access_token": token,
            })
            log.info("Authenticated as %s", user.get("username", "?"))
            # Subscribe to server-level voice events.
            await self._subscribe_server_events()
            # Check if already in a voice channel.
            await self._send_discord_command("GET_SELECTED_VOICE_CHANNEL")

        elif cmd_name == "GET_SELECTED_VOICE_CHANNEL":
            if response_data and response_data.get("id"):
                channel_id = response_data["id"]
                channel_name = response_data.get("name", "")
                guild_id = response_data.get("guild_id", "")
                await self._on_voice_channel_join(channel_id, channel_name, guild_id, response_data)
            else:
                await self._on_voice_channel_leave()

        elif cmd_name == "GET_VOICE_SETTINGS":
            await self.server.send({
                "type": "voice_settings",
                "mute": response_data.get("mute", False),
                "deaf": response_data.get("deaf", False),
            })

        elif cmd_name == "SET_VOICE_SETTINGS":
            await self.server.send({
                "type": "voice_settings",
                "mute": response_data.get("mute", False),
                "deaf": response_data.get("deaf", False),
            })

    async def _send_discord_command(
        self, cmd: str, args: dict[str, Any] | None = None
    ) -> None:
        """Send a command to Discord, tracking the nonce for response matching."""
        nonce_str = self.discord._next_nonce()
        payload: dict[str, Any] = {"cmd": cmd, "nonce": str(nonce_str)}
        if args:
            payload["args"] = args
        self._pending[str(nonce_str)] = cmd
        try:
            await asyncio.wait_for(
                self.discord.send_frame(OP_FRAME, payload), timeout=5
            )
        except asyncio.TimeoutError:
            self._pending.pop(str(nonce_str), None)
            log.warning("Timeout sending %s to Discord", cmd)

    # -- event subscriptions --

    async def _subscribe_server_events(self) -> None:
        """Subscribe to server-level events after authentication."""
        nonce = await self.discord.subscribe("VOICE_CHANNEL_SELECT")
        self._pending[nonce] = "SUB_VOICE_CHANNEL_SELECT"

        nonce = await self.discord.subscribe("VOICE_SETTINGS_UPDATE")
        self._pending[nonce] = "SUB_VOICE_SETTINGS_UPDATE"

    async def _subscribe_channel_events(self, channel_id: str) -> None:
        """Subscribe to voice events for a specific channel."""
        for evt in (
            "VOICE_STATE_CREATE",
            "VOICE_STATE_UPDATE",
            "VOICE_STATE_DELETE",
            "SPEAKING_START",
            "SPEAKING_STOP",
        ):
            nonce = await self.discord.subscribe(evt, {"channel_id": channel_id})
            self._pending[nonce] = f"SUB_{evt}"

    async def _unsubscribe_channel_events(self, channel_id: str) -> None:
        """Unsubscribe from voice events for a specific channel."""
        for evt in (
            "VOICE_STATE_CREATE",
            "VOICE_STATE_UPDATE",
            "VOICE_STATE_DELETE",
            "SPEAKING_START",
            "SPEAKING_STOP",
        ):
            try:
                nonce = await self.discord.unsubscribe(evt, {"channel_id": channel_id})
                self._pending[nonce] = f"UNSUB_{evt}"
            except Exception:
                pass

    # -- voice state management --

    async def _on_voice_channel_join(
        self, channel_id: str, channel_name: str, guild_id: str,
        channel_data: dict[str, Any] | None = None
    ) -> None:
        """Handle joining a voice channel."""
        # Unsubscribe from previous channel if any.
        if self.current_channel_id and self.current_channel_id != channel_id:
            await self._unsubscribe_channel_events(self.current_channel_id)

        self.current_channel_id = channel_id
        self.voice_users.clear()

        await self.server.send({
            "type": "voice_channel",
            "channel": {
                "id": channel_id,
                "name": channel_name,
                "guild_id": guild_id,
            },
        })

        # Parse initial voice states if provided.
        if channel_data and "voice_states" in channel_data:
            for vs in channel_data["voice_states"]:
                user = vs.get("user", {})
                voice = vs.get("voice_state", {})
                uid = user.get("id", "")
                if uid:
                    self.voice_users[uid] = {
                        "id": uid,
                        "username": user.get("username", ""),
                        "avatar": user.get("avatar", ""),
                        "nick": vs.get("nick", "") or user.get("username", ""),
                        "mute": voice.get("mute", False),
                        "self_mute": voice.get("self_mute", False),
                        "deaf": voice.get("deaf", False),
                        "self_deaf": voice.get("self_deaf", False),
                        "speaking": False,
                    }
            await self._send_voice_state()

        # Subscribe to this channel's events.
        await self._subscribe_channel_events(channel_id)

        # Also fetch current voice settings.
        await self._send_discord_command("GET_VOICE_SETTINGS")

    async def _on_voice_channel_leave(self) -> None:
        """Handle leaving a voice channel."""
        if self.current_channel_id:
            await self._unsubscribe_channel_events(self.current_channel_id)
        self.current_channel_id = None
        self.voice_users.clear()
        await self.server.send({"type": "voice_channel", "channel": None})

    async def _send_voice_state(self) -> None:
        """Send full voice state to QML."""
        users = list(self.voice_users.values())
        await self.server.send({"type": "voice_state", "users": users})

    # -- dispatch handler --

    async def _handle_dispatch(self, evt: str, data: dict[str, Any]) -> None:
        """Handle a DISPATCH event from Discord."""

        if evt == "VOICE_CHANNEL_SELECT":
            channel_id = data.get("channel_id")
            guild_id = data.get("guild_id", "")
            if channel_id:
                # Fetch channel details.
                await self._send_discord_command(
                    "GET_SELECTED_VOICE_CHANNEL"
                )
            else:
                await self._on_voice_channel_leave()

        elif evt == "VOICE_STATE_CREATE":
            user = data.get("user", {})
            voice = data.get("voice_state", {})
            uid = user.get("id", "")
            if uid:
                self.voice_users[uid] = {
                    "id": uid,
                    "username": user.get("username", ""),
                    "avatar": user.get("avatar", ""),
                    "nick": data.get("nick", "") or user.get("username", ""),
                    "mute": voice.get("mute", False),
                    "self_mute": voice.get("self_mute", False),
                    "deaf": voice.get("deaf", False),
                    "self_deaf": voice.get("self_deaf", False),
                    "speaking": False,
                }
                await self._send_voice_state()

        elif evt == "VOICE_STATE_UPDATE":
            user = data.get("user", {})
            voice = data.get("voice_state", {})
            uid = user.get("id", "")
            if uid and uid in self.voice_users:
                entry = self.voice_users[uid]
                entry["username"] = user.get("username", entry["username"])
                entry["avatar"] = user.get("avatar", entry["avatar"])
                entry["nick"] = data.get("nick", "") or user.get("username", entry["username"])
                entry["mute"] = voice.get("mute", entry["mute"])
                entry["self_mute"] = voice.get("self_mute", entry["self_mute"])
                entry["deaf"] = voice.get("deaf", entry["deaf"])
                entry["self_deaf"] = voice.get("self_deaf", entry["self_deaf"])
                await self._send_voice_state()

        elif evt == "VOICE_STATE_DELETE":
            user = data.get("user", {})
            uid = user.get("id", "")
            if uid and uid in self.voice_users:
                del self.voice_users[uid]
                await self._send_voice_state()

        elif evt == "SPEAKING_START":
            uid = data.get("user_id", "")
            if uid and uid in self.voice_users:
                self.voice_users[uid]["speaking"] = True
            await self.server.send({"type": "speaking", "user_id": uid, "speaking": True})

        elif evt == "SPEAKING_STOP":
            uid = data.get("user_id", "")
            if uid and uid in self.voice_users:
                self.voice_users[uid]["speaking"] = False
            await self.server.send({"type": "speaking", "user_id": uid, "speaking": False})

        elif evt == "VOICE_SETTINGS_UPDATE":
            await self.server.send({
                "type": "voice_settings",
                "mute": data.get("mute", False),
                "deaf": data.get("deaf", False),
            })

    # -- QML command handler --

    async def _handle_qml_command(self, msg: dict[str, Any]) -> None:
        """Handle a command from the QML plugin."""
        cmd = msg.get("cmd", "")

        if cmd == "connect":
            # Skip if already connected (auto-connect handles it).
            if not self.discord.connected and not self._gateway_mode:
                asyncio.ensure_future(self._do_connect_flow(msg.get("token", "")))

        elif cmd == "authorize":
            if not self.discord.connected and not self._gateway_mode:
                if not await self._connect_discord():
                    await self.server.send({"type": "error", "error": "Discord not running or IPC unavailable"})
                    return
            if self._gateway_mode:
                return  # Already connected via Gateway
            try:
                nonce = await self.discord.authorize(self.client_id, OAUTH_SCOPES)
                self._pending[nonce] = "AUTHORIZE"
            except Exception as e:
                log.error("Authorize failed: %s", e)
                await self.server.send({"type": "auth_error", "error": f"Authorize failed: {e}"})

        elif cmd == "login":
            # Interactive OAuth2 login - opens browser for user authorization
            if self._gateway_mode:
                return  # Already connected via Gateway
            asyncio.ensure_future(self._do_oauth2_login())

        elif cmd == "authenticate":
            token = msg.get("token", "")
            if not token:
                token = self.tokens.load() or ""
            if not token:
                await self.server.send({"type": "auth_required"})
                return
            if not self.discord.connected:
                if not await self._connect_discord():
                    return
            nonce = await self.discord.authenticate(token)
            self._pending[nonce] = "AUTHENTICATE"

        elif cmd == "set_voice_settings":
            if not self.authenticated:
                return
            args: dict[str, Any] = {}
            if "mute" in msg:
                args["mute"] = msg["mute"]
            if "deaf" in msg:
                args["deaf"] = msg["deaf"]
            if args:
                await self._send_discord_command("SET_VOICE_SETTINGS", args)

        elif cmd == "get_voice_settings":
            if self.authenticated:
                await self._send_discord_command("GET_VOICE_SETTINGS")

        elif cmd == "shutdown":
            await self.shutdown()

    async def _do_oauth2_login(self) -> None:
        """Run an interactive OAuth2 login to get a Discord token for Gateway mode."""
        if self._gateway_mode:
            return
        # Start local HTTP server for OAuth2 callback
        token = await asyncio.get_event_loop().run_in_executor(None, _oauth2_login)
        if token:
            log.info("OAuth2 login succeeded, starting Gateway...")
            asyncio.ensure_future(self._start_gateway(token))
        else:
            log.warning("OAuth2 login failed or timed out")
            await self.server.send({
                "type": "auth_error",
                "error": "Login failed. Try again or set DISCORD_TOKEN manually.",
            })

    async def _do_connect_flow(self, cached_token: str) -> None:
        """Full connection flow: connect with retry backoff, then try cached token or request auth."""
        if self.discord.connected:
            return
        retry_delays = [5, 10, 30, 60]
        attempt = 0

        while not self._shutdown:
            if await self._connect_discord(notify_qml=False):
                # Start reading from Discord in background.
                self._discord_task = asyncio.create_task(self._discord_read_loop())

                # Try cached token.
                token = cached_token or self.tokens.load()
                if token:
                    nonce = await self.discord.authenticate(token)
                    self._pending[nonce] = "AUTHENTICATE"
                else:
                    await self.server.send({"type": "auth_required"})
                return

            # Connection failed, retry with backoff.
            delay = retry_delays[min(attempt, len(retry_delays) - 1)]
            if attempt == 0:
                log.info("Discord unavailable, retrying in background every %ds...", delay)
            attempt += 1
            await asyncio.sleep(delay)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    if len(sys.argv) < 2:
        xdg_runtime = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
        socket_path = os.path.join(xdg_runtime, "dms-discord-voice.sock")
    else:
        socket_path = sys.argv[1]

    client_id = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_CLIENT_ID

    bridge = DiscordBridge(socket_path, client_id)
    asyncio.run(bridge.run())


if __name__ == "__main__":
    main()
