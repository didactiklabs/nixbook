"""immich-photo-manager-credentials: the Immich connection, for nixbook-shell's
Settings window. It saves where the server's own update_credentials tool does
(IMMICH_CACHE_DIR, ~/.immich-photo-manager/config.json, owner-only), which the
server reads before IMMICH_BASE_URL / IMMICH_API_KEY(_FILE) from Nix.

  show            {"base_url", "has_key", "source": "saved"|"nix"|"none"}
  set BASE_URL    the API key on stdin (empty: keep the current one), checked
                  against the server before it is saved
  clear           forget the saved connection (back to the Nix options)

Prints one JSON object; exits 1 with {"error"} when something fails. The key
is never printed.
"""

import asyncio
import json
import os
import sys

import httpx

from immich_mcp_server.client.base import ImmichClientBase, _real_env_value


def _saved() -> dict:
    return ImmichClientBase._load_config_override() or ImmichClientBase._load_stable_config()


def _current() -> tuple[str, str, str]:
    """(base_url, api_key, source) the server would start with."""
    saved = _saved()
    if saved.get("base_url") and saved.get("api_key"):
        return saved["base_url"], saved["api_key"], "saved"
    url = _real_env_value("IMMICH_BASE_URL")
    key = _real_env_value("IMMICH_API_KEY")
    if url or key:
        return url, key, "nix"
    return "", "", "none"


def _out(obj: dict, code: int = 0) -> None:
    print(json.dumps(obj))
    sys.exit(code)


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
    if args == ["show"]:
        url, key, source = _current()
        _out({"base_url": url, "has_key": bool(key), "source": source})
    if args == ["clear"]:
        for path in {ImmichClientBase._config_path(), ImmichClientBase._stable_config_path()}:
            if path and os.path.exists(path):
                os.remove(path)
        url, key, source = _current()
        _out({"base_url": url, "has_key": bool(key), "source": source})
    if len(args) == 2 and args[0] == "set":
        base_url = args[1].strip().rstrip("/")
        api_key = sys.stdin.readline().strip() or _current()[1]
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
        ImmichClientBase.save_config(base_url, api_key)
        _out({
            "base_url": base_url,
            "has_key": True,
            "source": "saved",
            "photos": stats.get("photos"),
            "videos": stats.get("videos"),
        })
    _out({"error": "usage: immich-photo-manager-credentials show | set BASE_URL (key on stdin) | clear"}, 1)


if __name__ == "__main__":
    main()
