.pragma library

// Listening along (services/MeshListen.qml), in plain code: whether the
// listener's player is on the host's song, and what to do about it. Pure
// JavaScript as QML's engine runs it (no ES2019+): tests/listen-along.sh
// runs it under node.
//
// The same song isn't always the same id: YouTube Music often plays a song
// opened by its video id under another one (the song's audio version for
// its music video, or the other way round), so the listener's player is on
// the host's song when the id matches or the title and the artist do.

// A title or an artist, compared loosely: no accents (Vietnamese ones
// included), no case, no "(Official Video)" or "[Lyrics]", no "feat. …",
// no punctuation.
function norm(text) {
    var s = String(text || "")
    if (typeof s.normalize === "function") s = s.normalize("NFD").replace(/[\u0300-\u036f]/g, "")
    s = s.replace(/[đĐ]/g, "d").toLowerCase()
    s = s.replace(/\([^)]*\)|\[[^\]]*\]/g, " ")
    s = s.replace(/\s(feat|ft|featuring)\.?\s.*$/, " ")
    s = s.replace(/\b(official|music video|video|audio|lyrics?|lyric video|mv|m\/v|hd|4k|visualizer|topic)\b/g, " ")
    s = s.replace(/[^a-z0-9]+/g, " ")
    return s.replace(/^\s+|\s+$/g, "")
}

function words(text) {
    var out = {}
    var list = norm(text).split(" ")
    for (var i = 0; i < list.length; i++) if (list[i].length >= 2) out[list[i]] = true
    return out
}

// a, b: { id, title, artist, length (s) }.
function sameSong(a, b) {
    if (!a || !b) return false
    if (a.id && b.id && a.id === b.id) return true
    var ta = norm(a.title), tb = norm(b.title)
    if (ta === "" || tb === "") return false
    var titled = ta === tb || (ta.length >= 4 && tb.indexOf(ta) >= 0) || (tb.length >= 4 && ta.indexOf(tb) >= 0)
    if (!titled) return false
    if (!a.artist || !b.artist) return true
    var wa = words(a.artist), wb = words(b.artist)
    for (var w in wa) if (wb[w]) return true
    // YouTube Music's artist line can be the channel's name: the same
    // title and length is enough then.
    return a.length > 0 && b.length > 0 && Math.abs(a.length - b.length) <= 5
}

function nearEnd(f) {
    return f.lastLen > 0 && f.lastPos > f.lastLen - 10
}

// The listener's player went away (no MPRIS player any more): "leave" |
// "wait" | "next" (waiting for the host's next song) | "reopen". An app gone for 5 s was closed by the listener (an app
// restarting itself comes back). The background player (nixbook-ytmusic)
// leaves the bus whenever it has nothing loaded: its one-song queue ends a
// little before the host's next song gets here (the host's state settles a
// tick, crosses the network, the song loads), and that used to read as the
// app closed, 5 s later, out of listening along. Gone at its song's end:
// waited for the host's next song, however long (the session's own end or
// expiry ends it); a next song from the host: opened; gone in the middle of
// the song (stopped from its controls) for 5 s: "leave". x: { now, wantId,
// background, target (s: where the host is) }.
function goneStep(f, x) {
    if (x.background) {
        if (f.syncedTo !== "" && f.syncedTo !== x.wantId) {
            f.goneSince = 0
            return "reopen"
        }
        if (f.syncedTo === x.wantId && nearEnd(f)) {
            f.goneSince = 0
            // The host started it again (repeat one, or back to it).
            if (x.target !== undefined && x.target < f.lastPos - 20) return "reopen"
            return "next"
        }
    }
    if (!f.goneSince) f.goneSince = x.now
    return x.now - f.goneSince >= 5000 ? "leave" : "wait"
}
// A new song to follow.
function fresh() {
    return { openedFor: "", openedAt: 0, opens: 0, syncedTo: "", offSince: 0, endSince: 0, pausedSince: 0, goneSince: 0, held: false, heldSince: 0,
        sawPlaying: false, cmdAt: 0, lastPos: 0, lastLen: 0, seekAt: 0, seekRecv: 0, seekedFor: "",
        tried: [], alt: "", altFor: "", before: "" }
}

// What to do this tick, about the song: { act: "sync" | "open" | "wait" |
// "leave" }. f: the follower's state (fresh(), changed here). x: { now
// (ms), wantId (the id to open), want (the host's track), cur (the
// listener's track, null for none) }.
function followStep(f, x) {
    // On it: the host's id, the other version opened in its place (alt:
    // the host's one wasn't playable here), or the same song by its title.
    if (x.cur && (x.cur.id === x.wantId || (f.altFor === x.wantId && f.alt && x.cur.id === f.alt)
            || sameSong(x.cur, x.want))) {
        f.offSince = 0
        f.endSince = 0
        return { act: "sync" }
    }
    if (f.syncedTo === x.wantId) {
        if (nearEnd(f)) {
            // It ended here first (autoplay, or the player stopped): the
            // host's next song is on its way. Not "something else".
            if (!f.endSince) f.endSince = x.now
            if (x.now - f.endSince < 30000) return { act: "wait" }
        } else if (x.cur && x.cur.id) {
            // Something else here, for 3 s (not a player's passing metadata
            // while it loads): the listener played it.
            if (!f.offSince) f.offSince = x.now
            if (x.now - f.offSince >= 3000) return { act: "leave", why: "other" }
            return { act: "wait" }
        }
    }
    if (f.openedFor !== x.wantId) {
        f.openedFor = x.wantId
        f.opens = 0
        f.tried = []
        f.alt = ""
        f.altFor = ""
    }
    // Once per song, at the host's position; a second time only if after
    // 12 s it still isn't on it (YouTube Music: another version of the song,
    // that one not playable here; Spotify: its first open after it starts
    // doesn't take), and that's all: never a retry loop.
    // The open landed on some other song (the player moved off what it
    // played, not to the host's): that try failed, the second one now
    // rather than in 12 s.
    var landedElsewhere = f.opens === 1 && x.cur && x.cur.id && x.cur.id !== f.before && x.now - f.openedAt > 1500
    if (f.opens === 0 || ((landedElsewhere || x.now - f.openedAt > 12000) && f.opens < 2)) {
        f.opens++
        f.openedAt = x.now
        f.before = x.cur ? x.cur.id : ""
        f.sawPlaying = false
        f.pausedSince = 0
        return { act: "open" }
    }
    return { act: "wait" }
}

// On the song, where to jump (seconds), or -1: once the song has opened
// (6 s: YouTube Music, given `&t=`, keeps the old position about 2 s, shows
// 0 at 3 s and lands on the link's time at 4 s, measured on totoro; a jump
// before that undid it), when the host's news
// comes (a seek, a pause, a resume), and else for a drift at most every
// 30 s; never more than every 4 s, nor at the song's end. A jump makes
// YouTube Music buffer again, which looks like the song reloading, so it is
// kept to those, and some slack is allowed (a network's delays): a drift
// under 5 s stays, the host's news and the first jump under 2.5 s and 3 s.
// Never while the player here isn't really playing yet (its position not
// moving: still loading, or Spotify reporting 0 right after it starts).
// x: { now, pos, target, len, hostRecv, playing }.
function seekStep(f, x) {
    var moving = x.playing && f.prevPos !== undefined && x.pos !== f.prevPos
    f.prevPos = x.pos
    if (x.now - f.openedAt < 6000 || (f.seekAt > 0 && x.now - f.seekAt < 4000)) return -1
    if (x.len > 0 && x.target >= x.len - 2) return -1
    var news = f.seekRecv !== x.hostRecv
    var first = f.seekedFor !== f.openedFor
    if (first && !moving) return -1
    f.seekRecv = x.hostRecv
    var drift = Math.abs(x.pos - x.target)
    var limit = first ? 3 : news ? 2.5 : 5
    if (!first && !news && x.now - f.seekAt <= 30000) return -1
    f.seekedFor = f.openedFor
    if (drift <= limit) return -1
    f.seekAt = x.now
    return Math.max(0, x.target)
}

// On the song, about play/pause: "ok" | "play" | "pause" | "hold" |
// "resume" | "leave". x: { now, hostPlaying, localPlaying, hostRecv (ms,
// the host's last state) }.
// Paused here while the host plays, after it played (once it lasts 8 s,
// not at the song's end — the next one comes —, nor right after a command,
// an open or the host's news): the listener paused (a media key, the
// panel's button, a click by mistake). It used to end listening along;
// now it is a hold: nothing is played for them ("hold" each tick; the
// host's next songs aren't opened either), and when they press play again
// it "resume"s, caught up to where the host is. Held 30 minutes: they've
// moved on, "leave".
var HOLD_MAX = 30 * 60 * 1000
function playStep(f, x) {
    if (f.held) {
        if (x.localPlaying) {
            f.held = false
            f.heldSince = 0
            f.pausedSince = 0
            f.sawPlaying = true
            return "resume"
        }
        return x.now - f.heldSince >= HOLD_MAX ? "leave" : "hold"
    }
    if (!x.hostPlaying) {
        f.pausedSince = 0
        if (x.localPlaying && x.now - f.cmdAt > 1500) {
            f.cmdAt = x.now
            f.sawPlaying = false
            return "pause"
        }
        return "ok"
    }
    if (x.localPlaying) {
        f.sawPlaying = true
        f.pausedSince = 0
        return "ok"
    }
    if (f.sawPlaying && !nearEnd(f) && x.now - f.cmdAt > 3000 && x.now - f.openedAt > 8000 && x.now - x.hostRecv > 3000) {
        if (!f.pausedSince) f.pausedSince = x.now
        if (x.now - f.pausedSince >= 8000) {
            f.held = true
            f.heldSince = x.now
            return "hold"
        }
        return "ok"
    }
    if (x.now - f.cmdAt > 2000) {
        f.cmdAt = x.now
        return "play"
    }
    return "ok"
}
