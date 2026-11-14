#!/usr/bin/env python3
"""lyrics.py TITLE ARTIST SECONDS [VIDEO_ID [NIXBOOK_YTMUSIC]]: a song's timed
lyrics, as "time§text§…§ok" (or not_found / no_info / error).

A YouTube Music song (VIDEO_ID) is asked from YouTube Music first
(`nixbook-ytmusic lyrics`): its timed lyrics are made for that recording.
Else lrclib, where a title has several entries of the same length whose
words start tens of seconds apart (TV cuts and videos filed under the
album's length): the entries of the song's length are compared and the
timing most of them agree on is taken."""
import json
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

AGENT = "nixbook-shell (https://github.com/didactiklabs/nixbook)"
NEAR = 2.0     # seconds of length an entry may differ from the song
AGREE = 1.5    # seconds two entries' first words may differ and still agree


def _parse_lrc(lrc_text: str) -> list:
    lines = []
    for raw in lrc_text.splitlines():
        raw = raw.strip()
        if not raw:
            continue
        try:
            tag_end = raw.index("]")
            time_str = raw[1:tag_end]
            text = raw[tag_end + 1:].strip()
            mins, secs = time_str.split(":")
            timestamp = int(mins) * 60 + float(secs)
            lines.append({"time": timestamp, "text": text})
        except Exception:
            continue
    return sorted(lines, key=lambda x: x["time"])


def _is_match(d: dict, title: str, artist: str) -> bool:
    if not d.get("syncedLyrics"):
        return False
    r_title  = (d.get("trackName")  or "").lower()
    r_artist = (d.get("artistName") or "").lower()
    t = title.lower()
    a = artist.lower()
    title_match = (t in r_title or r_title in t or
                   any(word in r_title for word in t.split() if len(word) > 3))
    artist_match = (a in r_artist or r_artist in a or
                    any(word in r_artist for word in a.split() if len(word) > 3))
    return title_match and artist_match


class Unreachable(Exception):
    """lrclib answered none of the requests (network down, timeouts)."""


def _first_words(lines: list) -> float:
    """When the words start (the first line that isn't empty or a note)."""
    for line in lines:
        if line["text"].strip(" ♪♫*-"):
            return line["time"]
    return lines[0]["time"] if lines else 0.0


def pick(candidates: list, title: str, duration: float) -> list:
    """The lines of the best entry among lrclib's ({duration, trackName,
    lines}, in lrclib's order): those of the song's length (else of the
    nearest length), an exact title before a loose one, then the timing most
    of them agree on (the first asked breaks a tie)."""
    candidates = [c for c in candidates if c.get("lines")]
    if not candidates:
        return []

    def off(c):
        d = c.get("duration")
        return abs(float(d) - duration) if duration > 0 and isinstance(d, (int, float)) else 1e6

    pool = [c for c in candidates if off(c) <= NEAR]
    if not pool:
        nearest = min(off(c) for c in candidates)
        pool = [c for c in candidates if off(c) <= nearest + 1]
    exact = [c for c in pool if (c.get("trackName") or "").strip().lower() == title.strip().lower()]
    pool = exact or pool
    groups = []  # [[start of its first entry, entries]]
    for c in pool:
        start = _first_words(c["lines"])
        for g in groups:
            if abs(g[0] - start) <= AGREE:
                g[1].append(c)
                break
        else:
            groups.append([start, [c]])
    best = max(groups, key=lambda g: len(g[1]))  # max keeps the first of equals
    return best[1][0]["lines"]


def _get(url: str):
    req = urllib.request.Request(url, headers={"User-Agent": AGENT})
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.loads(r.read().decode())


def fetch_lrclib(title: str, artist: str, duration: float) -> list:
    q = urllib.parse.quote
    urls = [
        f"https://lrclib.net/api/get?track_name={q(title)}&artist_name={q(artist)}&duration={int(duration)}",
        f"https://lrclib.net/api/search?track_name={q(title)}&artist_name={q(artist)}",
        f"https://lrclib.net/api/search?q={q(title + ' ' + artist)}",
    ]
    answered = False
    candidates = []
    for i, url in enumerate(urls):
        if i == 2 and candidates:
            break  # the loose search only when the two others found nothing
        try:
            try:
                data = _get(url)
            except urllib.error.HTTPError:
                answered = True  # 404: lrclib has no such song
                continue
            answered = True
            for d in data if isinstance(data, list) else [data]:
                if isinstance(d, dict) and _is_match(d, title, artist):
                    candidates.append({"duration": d.get("duration"), "trackName": d.get("trackName"),
                                       "lines": _parse_lrc(d["syncedLyrics"])})
        except Exception:
            continue
    lines = pick(candidates, title, duration)
    if not lines and not answered:
        raise Unreachable()
    return lines


def fetch_ytmusic(video: str, helper: str) -> list:
    """YouTube Music's timed lyrics of this recording ([] when it has none,
    or the helper isn't there)."""
    try:
        r = subprocess.run([helper, "lyrics", video], capture_output=True, text=True, timeout=25)
        data = json.loads(r.stdout or "{}")
    except Exception:
        return []
    if not isinstance(data, dict) or not data.get("timed"):
        return []
    return [{"time": float(l["time"]), "text": str(l.get("text") or "")} for l in data.get("lines") or []
            if isinstance(l, dict) and isinstance(l.get("time"), (int, float))]


def main():
    if len(sys.argv) < 4:
        print("no_info", flush=True)
        sys.exit(0)
    title    = sys.argv[1]
    artist   = sys.argv[2]
    duration = float(sys.argv[3])
    video    = sys.argv[4] if len(sys.argv) > 4 else ""
    helper   = sys.argv[5] if len(sys.argv) > 5 else "nixbook-ytmusic"
    if not title or not artist:
        print("no_info", flush=True)
        sys.exit(0)
    lines = fetch_ytmusic(video, helper) if video else []
    if not lines:
        try:
            lines = fetch_lrclib(title, artist, duration)
        except Unreachable:
            print("error", flush=True)
            sys.exit(0)
    if not lines:
        print("not_found", flush=True)
        sys.exit(0)
    parts = []
    for line in lines:
        parts.append(str(line["time"]))
        parts.append(line["text"].replace("§", ""))
    parts.append("ok")
    print("§".join(parts), flush=True)


if __name__ == "__main__":
    main()
