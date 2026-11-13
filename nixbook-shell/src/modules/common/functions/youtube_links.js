.pragma library

// YouTube links the shell opens itself instead of a browser tab (nixbook's
// opt-in nixbookShellConfig.youtubeLinks: the Zen extension in
// zen-youtube/ and the machine's http(s) link router): what a link is.
// A video goes to mpv (the right panel's YouTube tab shows it), a YouTube
// Music song or playlist to the background player (its YouTube Music tab).
// Anything else (the home page, a channel, a search) is null: it opens in
// the browser as usual.
//
// Pure JavaScript as QML's engine runs it (no ES2019+). package.nix puts it
// in the Zen extension without the pragma line; tests/youtube-links.sh runs
// it under node.

var VIDEO_ID = /^[A-Za-z0-9_-]{11}$/
var LIST_ID = /^[A-Za-z0-9_-]{2,64}$/
var VIDEO_HOSTS = ["youtube.com", "www.youtube.com", "m.youtube.com"]

// "a=1&b=2" → {a: "1", b: "2"} (the first of a repeated key).
function params(text) {
    var out = {}
    var parts = String(text || "").split("&")
    for (var i = 0; i < parts.length; i++) {
        if (parts[i] === "") continue
        var eq = parts[i].indexOf("=")
        var key = eq < 0 ? parts[i] : parts[i].slice(0, eq)
        var value = eq < 0 ? "" : parts[i].slice(eq + 1)
        try {
            key = decodeURIComponent(key)
            value = decodeURIComponent(value.replace(/\+/g, " "))
        } catch (e) {
            continue
        }
        if (!(key in out)) out[key] = value
    }
    return out
}

// t=/start= as YouTube writes it: "90", "90s", "1h2m3s"; 0 otherwise.
function seconds(text) {
    var t = String(text || "")
    if (/^[0-9]+s?$/.test(t)) return parseInt(t, 10)
    var m = t.match(/^(?:([0-9]+)h)?(?:([0-9]+)m)?(?:([0-9]+)s)?$/)
    if (!m || t === "") return 0
    return (parseInt(m[1] || "0", 10) * 3600) + (parseInt(m[2] || "0", 10) * 60) + parseInt(m[3] || "0", 10)
}

// {kind: "video"|"song"|"playlist", id, list, start}, or null.
//   video: youtube.com/watch?v=, /shorts/, /live/, /embed/; youtu.be/ID
//   song: music.youtube.com/watch?v= (list: the playlist it was played from)
//   playlist: music.youtube.com/playlist?list=
function linkTarget(url) {
    var m = String(url || "").trim().match(/^https?:\/\/([^\/?#]+)(\/[^?#]*)?(\?[^#]*)?(#.*)?$/i)
    if (!m) return null
    // No user@host: a link that only looks like YouTube's.
    if (m[1].indexOf("@") >= 0) return null
    var host = m[1].toLowerCase().replace(/:[0-9]+$/, "").replace(/\.$/, "")
    var path = (m[2] || "/").replace(/\/+$/, "") || "/"
    var q = params(m[3] ? m[3].slice(1) : "")
    var hash = params(m[4] ? m[4].slice(1) : "")
    var start = seconds(q.t || q.start || hash.t || "")
    if (host === "music.youtube.com") {
        if (path === "/watch" && VIDEO_ID.test(q.v || ""))
            return { kind: "song", id: q.v, list: LIST_ID.test(q.list || "") ? q.list : "", start: start }
        if (path === "/playlist" && LIST_ID.test(q.list || ""))
            return { kind: "playlist", id: "", list: q.list, start: 0 }
        return null
    }
    var id = ""
    if (VIDEO_HOSTS.indexOf(host) >= 0) {
        if (path === "/watch") id = q.v || ""
        else {
            var p = path.match(/^\/(?:shorts|live|embed|v)\/([A-Za-z0-9_-]{11})$/)
            if (p) id = p[1]
        }
    } else if (host === "youtu.be") {
        var b = path.match(/^\/([A-Za-z0-9_-]{11})$/)
        if (b) id = b[1]
    }
    return VIDEO_ID.test(id) ? { kind: "video", id: id, list: "", start: start } : null
}
