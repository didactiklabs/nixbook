#!/usr/bin/env bash
# Unlocks the login keyring with the password typed on the lock screen
# ($UNLOCK_PASSWORD), through the running gnome-keyring-daemon's control
# socket ($XDG_RUNTIME_DIR/keyring/control): the request pam_gnome_keyring
# sends at login. The daemon is the gnome-keyring user service; it used to
# be killed and replaced by a `--login` one, which never got `--start`, so
# the Secret Service went away until the next login.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Skip if already unlocked
if "${SCRIPT_DIR}/is_unlocked.sh"; then
  exit 0
fi

# Prompt for password if not provided (and asked from a terminal)
if [[ -z ${UNLOCK_PASSWORD} ]]; then
  # Fingerprint / security key unlocks have no password: nothing to unlock with.
  [[ -t 0 ]] || exit 0
  echo -n 'Login password: ' >&2
  read -rs UNLOCK_PASSWORD || exit 1
  echo '' >&2
  [[ -n ${UNLOCK_PASSWORD} ]] || exit 0
fi

# The password goes through the environment, never the command line.
UNLOCK_PASSWORD="${UNLOCK_PASSWORD}" exec python3 -c '
import os, socket, struct, sys

password = os.environb.get(b"UNLOCK_PASSWORD", b"")
path = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/run/user/%d" % os.getuid()), "keyring", "control")
# Packet: total length, GKD_CONTROL_OP_UNLOCK (1), the password as a
# length-prefixed string; all big-endian.
body = struct.pack(">II", 1, len(password)) + password
packet = struct.pack(">I", 4 + len(body)) + body

def read_exactly(sock, n):
    data = b""
    while len(data) < n:
        chunk = sock.recv(n - len(data))
        if not chunk:
            raise ConnectionError("control socket closed")
        data += chunk
    return data

try:
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.connect(path)
        sock.sendall(b"\0")  # the credentials byte (the daemon checks our uid)
        sock.sendall(packet)
        (size,) = struct.unpack(">I", read_exactly(sock, 4))
        reply = read_exactly(sock, size - 4)
        (result,) = struct.unpack(">I", reply[:4])
except (OSError, struct.error) as e:
    print("keyring unlock: %s" % e, file=sys.stderr)
    sys.exit(1)
if result != 0:  # GKD_CONTROL_RESULT_OK
    print("keyring unlock: the daemon refused (code %d)" % result, file=sys.stderr)
    sys.exit(1)
'
