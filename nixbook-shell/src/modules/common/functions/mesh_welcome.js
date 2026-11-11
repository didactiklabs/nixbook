.pragma library

// The mesh's welcome back (services/Mesh.qml, MeshNudge.qml), in plain code:
// which nudges wait for it, and how they are grouped. Pure JavaScript as
// QML's engine runs it (no ES2019+): tests/mesh-welcome.sh runs it under
// node.

var CUT_IN_AGE = 10 * 60 * 1000 // a nudge older than this missed its moment
var MAX_AGE = 7 * 86400 * 1000 // older than this: unread only
var CATCH_UP = 5000 // what comes this long after (re)connecting is catch-up
var SHOWN = 4 // lines on the card; "and N more" after

// Whether a nudge received now waits for the welcome back: it came while
// this desktop wasn't there — sent long ago, the listener catching up after
// (re)connecting, or the screen locked. x: { now, connectedAt, locked }.
function waits(m, x) {
    if (!m || m.mine || !m.quick) return false
    var age = x.now - m.time
    if (age > MAX_AGE) return false
    return age > CUT_IN_AGE || !!x.locked || x.now - (x.connectedAt || 0) < CATCH_UP
}

// The welcome's lines: one per sender, kind of nudge and audience (to you /
// to everyone), with how many, the latest first. Not one read since in the
// Mesh tab (readAt per conversation), nor deleted, nor gone out of date.
// x: { now, readAt: {conv: time}, nudgeOf(id), conversationOf(m), nameOf(id) }.
function groups(messages, x) {
    var byKey = {}
    var order = []
    for (var i = 0; i < messages.length; i++) {
        var m = messages[i]
        if (!m || !m.welcome || m.greeted || m.deleted || m.mine) continue
        var n = x.nudgeOf(m.quick)
        var conv = x.conversationOf(m)
        if (!n || m.time <= ((x.readAt || {})[conv] || 0) || x.now - m.time > MAX_AGE) continue
        var key = m.from + "|" + m.quick + "|" + (m.to === "" ? "everyone" : "me")
        if (!byKey[key]) {
            byKey[key] = { from: m.from, name: "", quick: m.quick, emoji: n.emoji, text: n.text, to: m.to,
                conv: conv, count: 0, time: 0 }
            order.push(key)
        }
        var g = byKey[key]
        g.count++
        if (m.time >= g.time) {
            g.time = m.time
            g.name = m.name || x.nameOf(m.from)
        }
    }
    var list = []
    for (var k = 0; k < order.length; k++) list.push(byKey[order[k]])
    list.sort(function (a, b) { return b.time - a.time })
    return list
}

// The messages held for it, once it shows (or is no longer due): never again.
function heldIds(messages) {
    var ids = []
    for (var i = 0; i < messages.length; i++) {
        var m = messages[i]
        if (m && m.welcome && !m.greeted && !m.mine) ids.push(m.mid)
    }
    return ids
}
