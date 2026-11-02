.pragma library

// What is said in DAI's bubble about a project or teach mode, in plain
// code (no model), in English, French, German and Vietnamese:
//   projectIntent(text, names) → {action: "open"|"pause", name} | null:
//     "work on the hackathon", "pause hackathon", "travaille sur X",
//     "mets X en pause", "arbeite an X", "X pausieren", "làm X", "tạm dừng X"…
//     only when X is one of `names` (the saved projects), whatever the case,
//     dashes or spaces: anything else is DAI's (or another command's).
//   teachIntent(text, recording) → "start" | "stop" | "cancel" | null:
//     "watch me", "regarde-moi faire", "schau mir zu", "xem tôi làm"… to
//     start; while recording, "done", "c'est fini", "fertig", "xong" to stop,
//     "never mind" / "laisse tomber" / "vergiss es" / "thôi" to cancel.
// ES5-style for QML's JavaScript engine (and node, for the tests).

function _clean(text) {
    return String(text === undefined || text === null ? "" : text).trim().toLowerCase()
        .replace(/^(hey |ok |okay )?(dai[,:]?\s+)?/, "")
        .replace(/^(please |pls |can you |could you |s'il te pla[iî]t,? |peux-tu |tu peux |bitte |kannst du |l[aà]m [oơ]n |h[aã]y )+/, "")
        .replace(/([,\s]+(please|pls|thanks|thank you|s'il te pla[iî]t|stp|svp|merci|bitte|danke|nh[eé]|nha|[dđ][iì]))+$/, "")
        .replace(/[.!?\s]+$/, "")
        .replace(/\s+/g, " ")
        .trim();
}

function _key(name) {
    return String(name).toLowerCase().replace(/[-_.\s]+/g, " ").trim();
}

// Articles and "project" words before the name.
var _lead = "(?:(?:the|my|our|le|la|les|l'|mon|ma|notre|das|die|den|dem|der|mein(?:e|em|en)?|unser(?:e|em)?|d[uự] [aá]n|c[aá]i) )?"
    + "(?:(?:project|projet|projekt|d[uự] [aá]n) )?";
var _tail = "(?: (?:project|projet|projekt))?";

var _open = [
    "(?:let'?s |i'?m going to |i'll |time to )?(?:work|working) on " + _lead + "(.+?)" + _tail,
    "(?:let'?s )?(?:get |go )?back to " + _lead + "(.+?)" + _tail,
    "(?:resume|continue|reopen|open|switch to|start) " + _lead + "(.+?) project",
    "(?:resume|continue|reopen) " + _lead + "(.+?)",
    "(?:open|switch to) (?:the |my )?project (.+?)",
    // French
    "(?:je |on )?(?:travaille|travailler|bosse|bosser|bossons|travaillons) sur " + _lead + "(.+?)",
    "(?:je )?(?:reprends|reprendre|reprenons|continue|continuer) " + _lead + "(.+?)",
    "(?:retour|retourne|revenons|reviens) (?:à|a|au|aux|sur) " + _lead + "(.+?)",
    "(?:ouvre|ouvrir|rouvre) (?:le |mon )?projet (.+?)",
    // German
    "(?:ich |wir )?(?:arbeite|arbeiten) (?:jetzt |weiter )?(?:an|am) " + _lead + "(.+?)",
    "(?:an|am) " + _lead + "(.+?) (?:arbeiten|weiterarbeiten)",
    "(?:weiter mit|zur[uü]ck zu|zur[uü]ck zum|zur[uü]ck zur) " + _lead + "(.+?)",
    "(?:[oö]ffne|starte) (?:das |mein )?projekt (.+?)",
    // Vietnamese
    "(?:l[aà]m (?:vi[eệ]c (?:v[oớ]i|v[eề]|cho) |ti[eế]p )|ti[eế]p t[uụ]c (?:l[aà]m )?|quay l[aạ]i (?:v[oớ]i )?|m[oở] d[uự] [aá]n )" + _lead + "(.+?)",
    "l[aà]m " + _lead + "(.+?)"
];
var _pause = [
    "(?:pause|park|shelve|close) " + _lead + "(.+?)" + _tail,
    "(?:stop working on|i'?m done with|done with|that'?s it for|enough) " + _lead + "(.+?)" + _tail,
    // French
    "(?:mets|mettre|mettons) " + _lead + "(.+?) en pause",
    "(?:pause|j'arr[eê]te|arr[eê]te|arr[eê]tons|ferme) (?:de travailler sur |(?:le |mon )?projet )?" + _lead + "(.+?)",
    "(?:j'ai fini avec|fini avec|assez de) " + _lead + "(.+?)",
    // German
    "(?:pausiere|pausier|parke|schlie(?:ß|ss)e) " + _lead + "(.+?)" + _tail,
    _lead + "(.+?) (?:pausieren|parken|schlie(?:ß|ss)en)",
    "(?:h[oö]r(?:e)? auf mit|fertig mit|schluss mit) " + _lead + "(.+?)",
    // Vietnamese
    "(?:t[aạ]m d[uừ]ng|d[uừ]ng|ngh[iỉ]|[dđ][oó]ng d[uự] [aá]n|th[oô]i l[aà]m) " + _lead + "(.+?)"
];

function _compile(list) {
    var out = [];
    for (var i = 0; i < list.length; i++) out.push(new RegExp("^" + list[i] + "$"));
    return out;
}
var _openRe = _compile(_open);
var _pauseRe = _compile(_pause);

function projectIntent(text, names) {
    var t = _clean(text);
    if (t.length === 0 || t.length > 100 || t.indexOf("\n") >= 0) return null;
    var byKey = {};
    for (var i = 0; i < (names || []).length; i++) byKey[_key(names[i])] = names[i];
    // Pausing first: "close the hackathon project" isn't opening it.
    var lists = [["pause", _pauseRe], ["open", _openRe]];
    for (var l = 0; l < lists.length; l++) {
        var res = lists[l][1];
        for (var r = 0; r < res.length; r++) {
            var m = res[r].exec(t);
            if (!m) continue;
            var name = byKey[_key(m[1])];
            if (name !== undefined) return { action: lists[l][0], name: name };
        }
    }
    return null;
}

var _teachStart = /^(?:(?:ok |okay )?(?:now )?watch me(?: do (?:it|this))?(?: once)?|let me show you(?: how)?(?: once)?|i'?ll show you(?: how)?(?: once)?|(?:learn|record) (?:this|what i do)|(?:regarde|observe)[- ]moi(?: faire)?(?: une fois)?|je (?:vais te|te) montre(?:r)?(?: comment)?(?: une fois)?|apprends (?:ça|ca)|schau mir zu|sieh mir zu|ich zeig(?:e)? (?:es |das )?dir(?: (?:das|es|einmal|wie))*|lern das|xem (?:t[oô]i|m[iì]nh|em) l[aà]m(?: n[eè])?|[dđ][eể] (?:t[oô]i|m[iì]nh|em) ch[iỉ] (?:cho )?(?:b[aạ]n|dai)|h[oọ]c c[aá]i n[aà]y)$/;
var _teachStop = /^(?:done|i'?m done|that'?s it|that'?s all|finished|stop watching|stop recording|c'est (?:fini|bon|tout)|fini|termin[eé]|voil[aà]|j'ai fini|arr[eê]te de regarder|fertig|das war'?s|ich bin fertig|xong(?: r[oồ]i)?|h[eế]t r[oồ]i|v[aậ]y th[oô]i)$/;
var _teachCancel = /^(?:never ?mind|cancel(?: (?:it|that|recording))?|forget it|laisse tomber|annule|oublie|vergiss es|abbrechen|th[oô]i|h[uủ]y(?: [dđ]i)?|b[oỏ] qua)$/;

function teachIntent(text, recording) {
    var t = _clean(text);
    if (t.length === 0 || t.length > 80) return null;
    if (recording) {
        if (_teachStop.test(t)) return "stop";
        if (_teachCancel.test(t)) return "cancel";
        return null;
    }
    return _teachStart.test(t) ? "start" : null;
}
