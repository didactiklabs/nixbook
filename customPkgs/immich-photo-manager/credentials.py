"""immich-photo-manager-credentials: the Immich API key, for nixbook-shell's
Settings window. The key is kept in the keyring (secret-tool,
service=immich-photo-manager), where the wrapper looks it up when neither
IMMICH_API_KEY nor IMMICH_API_KEY_FILE gives one; the server URL is a shell
setting (ai.immich.url), passed here as an argument.

  status          {"has_key", "key_source": "env"|"file"|"keyring"|null}
  save URL        the key on stdin (empty: keep the current one), checked
                  against the server, then saved in the keyring; also drops
                  what the chat's update_credentials set for the session
  forget          remove the key from the keyring (and that session override)

Prints one JSON object; exits 1 with {"error"} when something fails. The key
is never printed.
"""

import asyncio
import json
import os
import subprocess
import sys

import httpx

from immich_mcp_server.client.base import ImmichClientBase

SECRET_TOOL = "@secretTool@"
ATTRIBUTES = ["service", "immich-photo-manager"]


def _out(obj: dict, code: int = 0) -> None:
    print(json.dumps(obj))
    sys.exit(code)


def _status() -> dict:
    key = os.environ.get("IMMICH_API_KEY", "")
    return {"has_key": bool(key), "key_source": os.environ.get("IMMICH_API_KEY_SOURCE") if key else None}


def _drop_session_override() -> None:
    for path in {ImmichClientBase._config_path(), ImmichClientBase._stable_config_path()}:
        if path and os.path.exists(path):
            os.remove(path)


async def _check(base_url: str, api_key: str) -> dict:
    client = ImmichClientBase(base_url=base_url, api_key=api_key)
    try:
        await client._request("GET", "/users/me")
    except httpx.HTTPStatusError as exc:
        # A scoped key without user.read still proves it is valid.
        if exc.response.status_code != 403:
            raise
    try:
        return await client._request("GET", "/server/statistics")
    except httpx.HTTPError:
        return {}


def main() -> None:
    args = sys.argv[1:]
    if args == ["status"]:
        _out(_status())
    if args == ["forget"]:
        subprocess.run([SECRET_TOOL, "clear", *ATTRIBUTES], check=False)
        _drop_session_override()
        os.environ.pop("IMMICH_API_KEY", None)
        _out(_status())
    if len(args) == 2 and args[0] == "save":
        base_url = args[1].strip().rstrip("/")
        new_key = sys.stdin.readline().strip()
        api_key = new_key or os.environ.get("IMMICH_API_KEY", "")
        if not base_url.startswith(("http://", "https://")):
            _out({"error": "the URL must start with http:// or https://"}, 1)
        if not api_key:
            _out({"error": "an API key is needed"}, 1)
        try:
            stats = asyncio.run(_check(base_url, api_key))
        except httpx.HTTPStatusError as exc:
            _out({"error": f"Immich rejected the API key (HTTP {exc.response.status_code})"}, 1)
        except httpx.HTTPError as exc:
            _out({"error": f"couldn't reach Immich at {base_url}: {exc}"}, 1)
        if new_key:
            stored = subprocess.run(
                [SECRET_TOOL, "store", "--label=Immich API key (immich-photo-manager)", *ATTRIBUTES],
                input=new_key, text=True, capture_output=True,
            )
            if stored.returncode != 0:
                _out({"error": f"couldn't save the key in the keyring: {stored.stderr.strip()}"}, 1)
            os.environ["IMMICH_API_KEY"] = new_key
            os.environ["IMMICH_API_KEY_SOURCE"] = "keyring"
        _drop_session_override()
        _out({**_status(), "photos": stats.get("photos"), "videos": stats.get("videos")})
    _out({"error": "usage: immich-photo-manager-credentials status | save URL (key on stdin) | forget"}, 1)


if __name__ == "__main__":
    main()
