# --------------------------------------------------------------------------
# The right panel's features the agents had no way to: YouTube Music in the
# background (its tab: `nixbook-ytmusic`, the player without a window),
# listening along in the Mesh (services/MeshListen.qml, through the shell's
# `mesh` target, which the generic shell_ipc refuses: messages speak in the
# user's name), and the sound (services/Audio.qml's `audio` target, refused
# to shell_ipc too: it could unmute the microphone; services/EchoCancel.qml).
# Each tool reaches only its own functions of those targets, and asks the
# user (ask_user_yes) before what puts them in front of other people
# (sharing what they listen to) or turns their microphone back on.

def shell_do(target, fn, *args):
    """A shell IPC function that answers nothing (void): only its errors."""
    out = qs_ipc("call", "--", target, fn, *args).stdout.strip()
    if out.startswith("error:"):
        raise ToolError(out[6:].strip())
    if out.lower().startswith(("target not found", "function not found", "no running")):
        raise ToolError(f"the desktop shell can't do that ({out}): is nixbook-shell running and up to date?")


def ytmusic_call(*args, input=None, timeout=60):
    """`nixbook-ytmusic` and its JSON answer (an `error` is a ToolError)."""
    proc = run(["nixbook-ytmusic", *args], input=input, timeout=timeout, check=False)
    try:
        out = json.loads(proc.stdout or "null")
    except ValueError:
        out = None
    if isinstance(out, dict) and out.get("error"):
        raise ToolError(str(out["error"])[:500])
    if proc.returncode != 0 or out is None:
        raise ToolError((proc.stderr or "").strip()[-300:] or f"nixbook-ytmusic failed ({proc.returncode})")
    return out


YTMP_ACTIONS = ("status", "search", "playlists", "playlist", "play", "control", "add", "create", "offline")
YTMP_CONTROLS = ("play", "pause", "toggle", "next", "previous", "stop", "seek", "shuffle", "repeat", "volume")
YT_VIDEO = r"[A-Za-z0-9_-]{11}"
YT_PLAYLIST = r"[A-Za-z0-9_-]{2,64}"


def ytmp_tracks(tracks):
    """Songs as the player takes them (from search or playlist answers)."""
    if not isinstance(tracks, list) or not 1 <= len(tracks) <= 1000:
        raise ToolError("`tracks`: 1 to 1000 songs from a search or playlist answer ({videoId, title, artist…})")
    out = []
    for t in tracks:
        if not isinstance(t, dict) or not re.fullmatch(YT_VIDEO, str(t.get("videoId") or "")):
            raise ToolError("`tracks`: each a song with its videoId")
        out.append({k: t[k] for k in ("videoId", "title", "artist", "album", "duration", "art") if k in t})
    return out


@tool(
    "youtube_music_player",
    "shell",
    "YouTube Music in the background: the right panel's YouTube Music tab, the user's YouTube Music "
    "played by mpv without a window (the MPRIS player \"YouTube Music (background)\"), signed in "
    "with their browser's session. Not the YouTube Music app (`youtube_music` reads that one's library). "
    "status: signed in, the song playing, position, volume, shuffle/repeat. search {query}: songs then "
    "videos, each with its videoId. playlists: the user's (Liked Music `LM` first; `own`: songs can be "
    "added to it). playlist {playlist}: its songs. play {playlist, index?, shuffle?} a playlist from a "
    "song | {video} one song | {tracks, index?} songs from a search (the rest of the list after). "
    "control {what: play|pause|toggle|next|previous|stop|seek|shuffle|repeat|volume, value}: seek "
    "seconds, shuffle on|off|toggle, repeat none|playlist|track|cycle, volume 0-100 (this player's own, "
    "not the system's). add {playlist, video}: a song into one of the user's playlists (`LM` likes it; "
    "never twice: status already). create {title, video?}: a new private playlist. offline {op: "
    "status|keep|unkeep, playlist}: songs kept on this computer for listening without network.",
    obj({
        "action": {"type": "string", "enum": list(YTMP_ACTIONS)},
        "query": {"type": "string", "description": "search: the words"},
        "playlist": {"type": "string", "description": "playlist, play, add, offline: a playlist id (LM: Liked Music)"},
        "video": {"type": "string", "description": "play, add, create: a song's videoId"},
        "tracks": {"type": "array", "items": {"type": "object"}, "description": "play: songs from a search answer"},
        "index": {"type": "integer", "description": "play: which song to start from (0 = the first)"},
        "shuffle": {"type": "boolean", "description": "play: shuffled"},
        "what": {"type": "string", "enum": list(YTMP_CONTROLS), "description": "control: what to do"},
        "value": {"type": ["string", "number"], "description": "control: seek seconds, volume 0-100, shuffle on|off|toggle, repeat mode"},
        "title": {"type": "string", "description": "create: the playlist's name"},
        "op": {"type": "string", "enum": ["status", "keep", "unkeep"], "description": "offline: what to do"},
    }, ["action"]),
    props={"action": "status|search|playlists|playlist|play|control|add|create|offline"},
    brief="YouTube Music in the background (the right panel's tab, no window): search, the user's playlists, "
          "play, controls and its own volume, add a song to a playlist, offline songs.",
)
def t_youtube_music_player(ctx, args):
    action = as_str(args, "action", max_len=16)
    if action not in YTMP_ACTIONS:
        raise ToolError("`action`: " + ", ".join(YTMP_ACTIONS))
    if action == "status":
        return [text(ytmusic_call("status"))]
    if action == "search":
        words = as_str(args, "query", max_len=200).split()
        return [text(ytmusic_call("search", *words))]
    if action == "playlists":
        out = ytmusic_call("playlists")
        # Their pictures are the panel's (cached files): not the agent's business.
        for p in out.get("playlists") or []:
            p.pop("thumb", None)
        return [text(out)]
    if action == "playlist":
        out = ytmusic_call("playlist", as_str(args, "playlist", max_len=64, pattern=YT_PLAYLIST))
        for t in out.get("tracks") or []:
            t.pop("thumb", None)
        return [text(out)]
    ctx.guard.check_rate()
    if action == "play":
        index = args.get("index", 0)
        if not isinstance(index, int) or isinstance(index, bool) or not 0 <= index < 1000:
            raise ToolError("`index`: a song's place in the list, from 0")
        if args.get("tracks") is not None:
            req = {"tracks": ytmp_tracks(args["tracks"]), "index": index, "shuffle": bool(args.get("shuffle"))}
            return [text(ytmusic_call("play-tracks", input=json.dumps(req)))]
        if args.get("video"):
            return [text(ytmusic_call("play-id", as_str(args, "video", pattern=YT_VIDEO)))]
        pid = as_str(args, "playlist", max_len=64, pattern=YT_PLAYLIST)
        return [text(ytmusic_call("play", pid, "--index", str(index), *(["--shuffle"] if args.get("shuffle") else [])))]
    if action == "control":
        what = as_str(args, "what", max_len=16)
        if what not in YTMP_CONTROLS:
            raise ToolError("`what`: " + ", ".join(YTMP_CONTROLS))
        argv = ["control", what]
        value = args.get("value")
        if what in ("seek", "volume"):
            if not isinstance(value, (int, float)) or isinstance(value, bool) or value < 0 \
                    or (what == "volume" and value > 100) or value > 86400:
                raise ToolError("`value`: seconds for seek, 0-100 for volume")
            argv.append(f"{value:g}")
        elif what in ("shuffle", "repeat") and value is not None:
            allowed = ("on", "off", "toggle") if what == "shuffle" else ("none", "playlist", "track", "cycle")
            if str(value) not in allowed:
                raise ToolError(f"`value` for {what}: " + "|".join(allowed))
            argv.append(str(value))
        return [text(ytmusic_call(*argv))]
    if action == "add":
        return [text(ytmusic_call("add", as_str(args, "playlist", max_len=64, pattern=YT_PLAYLIST),
                                  as_str(args, "video", pattern=YT_VIDEO)))]
    if action == "create":
        title = as_str(args, "title", max_len=150).split()
        video = [as_str(args, "video", pattern=YT_VIDEO)] if args.get("video") else []
        return [text(ytmusic_call("create", *title, *video))]
    op = args.get("op") or "status"
    if op == "status":
        return [text(ytmusic_call("offline", "status"))]
    if op not in ("keep", "unkeep"):
        raise ToolError("`op`: status, keep or unkeep")
    return [text(ytmusic_call("offline", op, as_str(args, "playlist", max_len=64, pattern=YT_PLAYLIST)))]


YTV_ACTIONS = ("home", "new", "subscriptions", "channel", "playlist", "search", "watch", "status", "control", "seen",
               "subscribe", "unsubscribe")
YTV_TABS = ("latest", "popular", "sections", "shorts", "live", "playlists")
YTV_CONTROLS = ("play", "pause", "toggle", "stop", "seek", "volume")
YT_CHANNEL = r"https://(www\.|m\.)?youtube\.com/(channel/UC[A-Za-z0-9_-]{22}|@[^/?#\s]{1,100}|c/[^/?#\s]{1,100}|user/[^/?#\s]{1,100})/?"


def ytv_count(args, default=20):
    n = args.get("count", default)
    if not isinstance(n, int) or isinstance(n, bool) or not 1 <= n <= 150:
        raise ToolError("`count`: 1 to 150 videos")
    return n


def ytv_videos(out):
    """A list of videos for the agent: its pictures are the panel's."""
    for v in out.get("items") or []:
        v.pop("thumb", None)
    return out


@tool(
    "youtube_videos",
    "shell",
    "YouTube videos, as the right panel's YouTube tab shows them, played in the user's mpv (a window "
    "with their mpv settings), never a browser. Reading needs the YouTube session YouTube Music signs "
    "in with (search doesn't). home {count?}: the user's YouTube home page. new {count?}: their "
    "subscriptions' videos they haven't seen yet (not in their YouTube watch history, not played from "
    "the tab, not marked seen), newest first, the last 30 days, each with published (approximate unix "
    "time) and channelId. seen {videos: [ids]}: marks videos seen (out of new). subscriptions: the channels "
    "they're subscribed to ({id, name, url, followers}). channel {channel, tab?, query?, count?}: a "
    "channel's tab — latest (default: newest first), sections (its home page's shelves, each a "
    "playlist: {id, title}), popular (most viewed), shorts, live, playlists ({id, title}) — or a search in it (query); its link from subscriptions or a video's channelUrl, or "
    "a video id: its channel. playlist {playlist, count?}: a playlist's videos. search {query, count?}. Videos come with id, title, channel, channelUrl, duration "
    "(seconds), views, live. watch {video}: plays a video id in mpv, at the volume the user last set "
    "for videos; the background music pauses. status: the video playing (title, videoId, Playing/"
    "Paused, position, length, volume 0-100) or null. control {what: play|pause|toggle|stop|seek|"
    "volume, value}: seek seconds from the start, volume 0-100 (that video's own, remembered for the "
    "next one; not the system's). subscribe|unsubscribe {channel}: the user's subscription to a channel "
    "(its link or id: UC…).",
    obj({
        "action": {"type": "string", "enum": list(YTV_ACTIONS)},
        "query": {"type": "string", "description": "search: the words; channel: a search in that channel"},
        "channel": {"type": "string", "description": "channel: its youtube.com link, or a video id; subscribe, unsubscribe: its link or id (UC…)"},
        "tab": {"type": "string", "enum": list(YTV_TABS), "description": "channel: which of its tabs (latest by default)"},
        "playlist": {"type": "string", "description": "playlist: its id (from a channel's playlists)"},
        "video": {"type": "string", "description": "watch: the video's id"},
        "videos": {"type": "array", "items": {"type": "string"}, "description": "seen: the videos' ids"},
        "count": {"type": "integer", "description": "home, new, channel, search: how many videos (1-150, 20 by default)"},
        "what": {"type": "string", "enum": list(YTV_CONTROLS), "description": "control: what to do"},
        "value": {"type": "number", "description": "control: seek seconds, volume 0-100"},
    }, ["action"]),
    props={"action": "home|new|subscriptions|channel|playlist|search|watch|status|control|seen|subscribe|unsubscribe"},
    brief="YouTube videos played in the user's mpv (the right panel's YouTube tab): their home page, "
          "their subscriptions' new videos not seen yet, subscribed channels, a channel's latest videos, search; watch, pause, seek, its own volume; "
          "subscribe to a channel.",
)
def t_youtube_videos(ctx, args):
    action = as_str(args, "action", max_len=16)
    if action not in YTV_ACTIONS:
        raise ToolError("`action`: " + ", ".join(YTV_ACTIONS))
    if action == "home":
        return [text(ytv_videos(ytmusic_call("videos", "home", "--count", str(ytv_count(args)), timeout=120)))]
    if action == "new":
        return [text(ytv_videos(ytmusic_call("videos", "new", "--count", str(ytv_count(args)), timeout=180)))]
    if action == "subscriptions":
        out = ytmusic_call("videos", "channels", timeout=120)
        for c in out.get("channels") or []:
            c.pop("avatar", None)
        return [text(out)]
    if action == "channel":
        ref = as_str(args, "channel", max_len=200)
        if not (re.fullmatch(YT_VIDEO, ref) or re.fullmatch(YT_CHANNEL, ref)):
            raise ToolError("`channel`: a YouTube channel's link (youtube.com/channel/UC…, /@name) or a video id")
        tab = args.get("tab") or "latest"
        if tab not in YTV_TABS:
            raise ToolError("`tab`: " + ", ".join(YTV_TABS))
        argv = ["videos", "channel", ref.rstrip("/"), "--count", str(ytv_count(args)), "--tab", tab]
        if args.get("query"):
            words = as_str(args, "query", max_len=200).split()
            if words:
                argv += ["--query", *words]
        return [text(ytv_videos(ytmusic_call(*argv, timeout=120)))]
    if action == "playlist":
        pid = as_str(args, "playlist", max_len=64, pattern=r"[A-Za-z0-9_-]{10,64}")
        return [text(ytv_videos(ytmusic_call("videos", "playlist", pid, "--count", str(ytv_count(args)), timeout=120)))]
    if action == "search":
        words = as_str(args, "query", max_len=200).split()
        if not words:
            raise ToolError("`query`: the words to search for")
        return [text(ytv_videos(ytmusic_call("videos", "search", *words, "--count", str(ytv_count(args)), timeout=120)))]
    if action == "status":
        try:
            return [text(json.loads(widget_call("youtubeMusic", "videoStatus")))]
        except ValueError:
            raise ToolError("the desktop shell didn't answer about the video")
    ctx.guard.check_rate()
    if action in ("subscribe", "unsubscribe"):
        ref = as_str(args, "channel", max_len=200)
        cid = ref if re.fullmatch(r"UC[A-Za-z0-9_-]{22}", ref) else ""
        if not cid:
            if not re.fullmatch(YT_CHANNEL, ref):
                raise ToolError("`channel`: a YouTube channel's link (youtube.com/channel/UC…, /@name) or its id (UC…)")
            # An @name: its id from its page.
            page = ytmusic_call("videos", "channel", ref.rstrip("/"), "--count", "1", timeout=120)
            cid = (re.search(r"/channel/(UC[A-Za-z0-9_-]{22})", str((page.get("channel") or {}).get("url") or "")) or [None, ""])[1]
            if not cid:
                raise ToolError("YouTube didn't say which channel that is")
        return [text(ytmusic_call("videos", action, cid, timeout=60))]
    if action == "seen":
        ids = args.get("videos")
        if not isinstance(ids, list) or not 1 <= len(ids) <= 150 \
                or not all(isinstance(i, str) and re.fullmatch(YT_VIDEO, i) for i in ids):
            raise ToolError("`videos`: 1 to 150 YouTube video ids")
        return [text(ytmusic_call("videos", "seen", *ids, timeout=30))]
    if action == "watch":
        widget_call("youtubeMusic", "watch", as_str(args, "video", pattern=YT_VIDEO))
        return [text("Opening the video in mpv (it shows in a few seconds); status says when it plays.")]
    what = as_str(args, "what", max_len=16)
    if what not in YTV_CONTROLS:
        raise ToolError("`what`: " + ", ".join(YTV_CONTROLS))
    value = args.get("value")
    if what in ("seek", "volume"):
        if not isinstance(value, (int, float)) or isinstance(value, bool) or value < 0 \
                or (what == "volume" and value > 100) or value > 86400:
            raise ToolError("`value`: seconds for seek, 0-100 for volume")
    widget_call("youtubeMusic", "videoControl", what, f"{value:g}" if what in ("seek", "volume") else "")
    return [text("ok")]


MESH_MEMBER = r"[A-Za-z0-9_.@-]{1,64}"


def mesh_listen_status():
    try:
        return json.loads(widget_call("mesh", "listenStatus"))
    except ValueError:
        raise ToolError("the desktop shell didn't answer about listening along")


@tool(
    "listen_along",
    "shell",
    "Listening together in the Mesh (the right panel's Mesh tab): a friend shares what their YouTube "
    "Music or Spotify plays and the user's player follows it, same song, same moment. status: what is "
    "shared with the user (sessions: host, track, playing), whether the user listens along (following, "
    "status) or shares their own (hosting, track), and the last notice (why listening along stopped). "
    "join {member}: listen along with that member's session (status names them: `host`). leave: stop "
    "listening along. share {member, '' = everyone}: share what the user plays with them (asked to the "
    "user first: it shows other people what they listen to). stop: stop sharing.",
    obj({
        "action": {"type": "string", "enum": ["status", "join", "leave", "share", "stop"]},
        "member": {"type": "string", "description": "join: the host; share: who to share with ('' = everyone)"},
    }, ["action"]),
)
def t_listen_along(ctx, args):
    action = as_str(args, "action", max_len=8)
    if action == "status":
        return [text(mesh_listen_status())]
    ctx.guard.check_rate()
    if action == "join":
        member = as_str(args, "member", max_len=64, pattern=MESH_MEMBER)
        out = widget_call("mesh", "listenJoin", member)
    elif action == "leave":
        out = widget_call("mesh", "listenLeave")
    elif action == "stop":
        out = widget_call("mesh", "listenStop")
    elif action == "share":
        member = args.get("member") or ""
        if member and not (isinstance(member, str) and re.fullmatch(MESH_MEMBER, member)):
            raise ToolError("`member`: a mesh member's id, or '' for everyone")
        ask_user_yes(ctx, f"Let the agent share what you listen to with {member or 'everyone in the mesh'}?",
                     "They'll see each song you play (title, artist, cover) and can listen along, until you stop "
                     "sharing.", key=f"listen:share:{member or 'everyone'}",
                     label=f"Share your music with {member or 'everyone'}")
        out = widget_call("mesh", "listenShare", member)
    else:
        raise ToolError("`action`: status, join, leave, share or stop")
    if out.startswith("error:"):
        raise ToolError(out[6:].strip())
    return [text(out[3:].strip() if out.startswith("ok:") else out)]


SOUND_ACTIONS = ("status", "volume", "mute", "unmute", "mic_mute", "mic_unmute", "echo_cancel")


@tool(
    "sound",
    "shell",
    "The user's sound, as the right panel's sliders and quick toggles set it. status: the output "
    "(device, volume %, muted), the microphones (muted: every one of them; each device), echo "
    "cancellation (active, its mic). volume {percent 0-100}: the output volume (no sudden jump: the "
    "shell's audio protection still applies). mute / unmute: the output. mic_mute: every microphone at "
    "once (the default one alone would leave the others live). mic_unmute: asked to the user first. "
    "echo_cancel {on}: keeps what plays out of the microphone (calls while music plays).",
    obj({
        "action": {"type": "string", "enum": list(SOUND_ACTIONS)},
        "percent": {"type": "integer", "description": "volume: 0-100"},
        "on": {"type": "boolean", "description": "echo_cancel: on or off"},
    }, ["action"]),
)
def t_sound(ctx, args):
    action = as_str(args, "action", max_len=16)
    if action not in SOUND_ACTIONS:
        raise ToolError("`action`: " + ", ".join(SOUND_ACTIONS))
    if action == "status":
        try:
            status = json.loads(widget_call("audio", "status"))
            status["echoCancellation"] = json.loads(widget_call("echoCancel", "status"))
        except ValueError:
            raise ToolError("the desktop shell didn't answer about the sound")
        return [text(status)]
    ctx.guard.check_rate()
    if action == "volume":
        pct = args.get("percent")
        if not isinstance(pct, int) or isinstance(pct, bool) or not 0 <= pct <= 100:
            raise ToolError("`percent`: 0 to 100")
        out = widget_call("audio", "setVolume", str(pct))
    elif action in ("mute", "unmute"):
        out = widget_call("audio", "outputMute", "true" if action == "mute" else "false")
    elif action == "mic_mute":
        shell_do("audio", "micMute")
        out = "ok: every microphone muted"
    elif action == "mic_unmute":
        # The microphone back on: the user's own yes, every time (no Always).
        ask_user_yes(ctx, "Let the agent turn your microphone back on?",
                     "Every microphone would hear again (calls, recordings, any app that listens).")
        shell_do("audio", "micUnmute")
        out = "ok: microphones on"
    else:
        on = args.get("on")
        if not isinstance(on, bool):
            raise ToolError("`on` must be true or false")
        shell_do("echoCancel", "on" if on else "off")
        out = f"ok: echo cancellation {'on' if on else 'off'}"
    if out.startswith("error:"):
        raise ToolError(out[6:].strip())
    return [text(out[3:].strip() if out.startswith("ok:") else out)]
