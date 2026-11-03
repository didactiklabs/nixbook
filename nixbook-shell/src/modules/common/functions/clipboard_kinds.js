.pragma library

// What a copied text is, in plain code (services/SmartClipboard.qml, the
// smart clipboard): a few milliseconds, no model. classify(text, opts) gives
// {secret, why, candidates}: never anything for a secret (a password, a
// one-time code, a key, a card number), else the kinds the text matches,
// best first, each with its actions (ids the shell labels and runs; `model`
// ones need the AI). Pure JavaScript as QML's engine runs it (no ES2019+,
// no \p{L}, no lookbehind): tests/smart-clipboard.sh runs it under node.
//
// opts: { now (a Date; tests), lang (the user's: en|fr|de|vi), known (other
// languages they read), app (the focused app id), currency (theirs, "" =
// from lang) }.

var KINDS = ["url", "email", "tracking", "phone", "error", "code", "date", "address", "amount", "language", "paragraph"]

// ── Secrets: never offered (and never sent anywhere) ─────────────────────
// The same password managers desktop-mcp refuses (PASSWORD_APP_NAMES).
var PASSWORD_APPS = /keepass|bitwarden|vaultwarden|1password|enpass|proton-?pass|lastpass|dashlane|keeper|nordpass|roboform|passbolt|seahorse|kwallet|authenticator|authy|rbw|gopass|qtpass|aegis|2fas/i
// desktop-mcp's NOTICE_SECRET (codes, bank and payment words), and its
// SECRET_PATTERNS' keys and tokens.
var NOTICE_SECRET = new RegExp(
    "\\b(otp|2fa|one[- ]time|verification|security|login|sign[- ]in|confirmation|passcode|code)\\b[^\\n]{0,40}\\b\\d{4,8}\\b"
    + "|\\b\\d{4,8}\\b[^\\n]{0,40}\\b(code|otp|verification|passcode)\\b"
    + "|code de (vérification|confirmation|sécurité)|mot de passe|bestätigungscode|mã (xác (nhận|minh)|otp)|mật khẩu"
    + "|\\b(iban|bic|card ending|carte se terminant)\\b", "i")
var SECRET_TOKENS = new RegExp(
    "-----BEGIN [A-Z0-9 ]*PRIVATE KEY|-----BEGIN PGP PRIVATE"
    + "|\\bsk-(ant-|proj-|live-|test-)?[A-Za-z0-9_\\-]{16,}|\\b(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})"
    + "|\\b(glpat-[A-Za-z0-9_\\-]{20,}|xox[abpors]-[A-Za-z0-9\\-]{10,}|AIza[0-9A-Za-z_\\-]{35}|hf_[A-Za-z0-9]{30,}|npm_[A-Za-z0-9]{30,})"
    + "|\\b(AKIA|ASIA)[0-9A-Z]{16}\\b|\\beyJ[A-Za-z0-9_\\-]{8,}\\.[A-Za-z0-9_\\-]{8,}\\.[A-Za-z0-9_\\-]{8,}"
    + "|\\b(bearer)\\s+[A-Za-z0-9._~+/=\\-]{12,}|\\bauthorization\\s*:"
    + "|[a-z][a-z0-9+.\\-]{0,20}://[^/\\s:@]{1,100}:[^@\\s/]{1,200}@"
    + "|\\b[\\w.\\-]{0,40}(token|secret|api[_\\-]?key|apikey|access[_\\-]?key|private[_\\-]?key|client[_\\-]?secret|password|passwd|passphrase|passwort|kennwort)[\\w.\\-]{0,40}[\"']?\\s*[=:]\\s*\\S"
    + "|(mot de passe|mật khẩu)\\s*[=:]\\s*\\S", "i")

function luhn(digits) {
    var sum = 0, alt = false
    for (var i = digits.length - 1; i >= 0; i--) {
        var n = digits.charCodeAt(i) - 48
        if (alt) { n *= 2; if (n > 9) n -= 9 }
        sum += n
        alt = !alt
    }
    return sum % 10 === 0
}

// Why `t` must never be offered, or "".
function secretWhy(t, app) {
    if (app && PASSWORD_APPS.test(app)) return "password manager"
    if (SECRET_TOKENS.test(t)) return "key or token"
    if (NOTICE_SECRET.test(t)) return "code or password"
    var s = t.trim()
    // A one-time code: 4 to 8 digits alone ("123 456" too).
    if (/^\d{4,8}$/.test(s) || /^\d{3}[ -]\d{3}$/.test(s)) return "one-time code"
    // A card number (13 to 19 digits, Luhn) or an IBAN.
    var digits = s.replace(/[ -]/g, "")
    if (/^\d{13,19}$/.test(digits) && /^[\d -]+$/.test(s) && luhn(digits) && !/fedex/i.test(t)) return "card number"
    var compact = s.replace(/ /g, "")
    if (/^[A-Z]{2}\d{2}[A-Z0-9]{11,30}$/.test(compact) && (compact.match(/\d/g) || []).length >= 10) return "bank account"
    // One word that reads like a password or a key: lower and upper case
    // and digits, or a symbol with letters and digits, or a long run of
    // base64 / hex. Tracking numbers (upper case and digits) aren't.
    if (!/\s/.test(s) && s.length >= 8 && s.length <= 200 && !isUrl(s) && !emailOf(s) && !/^(tel|sms|mailto|geo):/i.test(s)) {
        var lower = /[a-z]/.test(s), upper = /[A-Z]/.test(s), digit = /\d/.test(s)
        var symbol = /[!@#$%^&*()+=\[\]{};:'"\\|,<>?~`]/.test(s)
        if (lower && upper && digit) return "password"
        if (symbol && (lower || upper) && digit) return "password"
        if (s.length >= 20 && /^[A-Za-z0-9+\/_=\-]+$/.test(s) && lower && digit) return "token"
        if (/^[0-9a-f]{32,}$/i.test(s)) return "key"
    }
    return ""
}

// ── Links and addresses ───────────────────────────────────────────────────
function isUrl(s) {
    return /^(https?:\/\/|www\.)[^\s<>"]+$/i.test(s)
}
function emailOf(s) {
    var m = /^(?:mailto:)?([A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,})$/.exec(s)
        || /^[^<>@\n]{0,60}<([A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,})>$/.exec(s)
    return m ? m[1] : ""
}
function urlKind(s) {
    var u = s.replace(/[)\].,;:!?»"']+$/, "")
    if (!isUrl(u)) return null
    if (!/^https?:/i.test(u)) u = "https://" + u
    var host = (/^https?:\/\/([^\/?#:]+)/i.exec(u) || ["", ""])[1].toLowerCase()
    // A private address, or a link carrying a key or a code: opened, never
    // sent to a model.
    var local = /^(localhost|127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|\[?::1)|\.(local|lan|home|internal)$/.test(host)
    var keyed = /[?&#](token|key|apikey|api_key|access_token|code|sig|signature|secret|password|auth)=/i.test(u)
    var actions = []
    if (!local && !keyed) actions.push({ id: "summarizePage", model: true, url: u })
    actions.push({ id: "open", model: false, url: u })
    return { kind: "url", detail: host.replace(/^www\./, ""), url: u, actions: actions }
}

// ── Tracking numbers ──────────────────────────────────────────────────────
var CARRIERS = {
    ups: { name: "UPS", url: "https://www.ups.com/track?tracknum=" },
    fedex: { name: "FedEx", url: "https://www.fedex.com/fedextrack/?trknbr=" },
    dhl: { name: "DHL", url: "https://www.dhl.com/global-en/home/tracking/tracking-parcel.html?submit=1&tracking-id=" },
    laposte: { name: "La Poste", url: "https://www.laposte.fr/outils/suivre-vos-envois?code=" },
    colissimo: { name: "Colissimo", url: "https://www.laposte.fr/outils/suivre-vos-envois?code=" },
    chronopost: { name: "Chronopost", url: "https://www.chronopost.fr/tracking-no-cms/suivi-page?listeNumerosLT=" },
    other: { name: "", url: "https://t.17track.net/en#nums=" }
}
// UPS: 1Z + 16, its last character a check digit (letters as (code-63)%10).
function upsValid(n) {
    var body = n.slice(2, 17), sum = 0
    for (var i = 0; i < body.length; i++) {
        var c = body.charAt(i)
        var v = /\d/.test(c) ? Number(c) : (c.charCodeAt(0) - 63) % 10
        sum += i % 2 === 1 ? v * 2 : v
    }
    return (10 - sum % 10) % 10 === Number(n.charAt(17))
}
// The UPU S10 format (RR123456789FR): its 9th digit checks the first 8.
function s10Valid(n) {
    var w = [8, 6, 4, 2, 3, 5, 9, 7], sum = 0
    for (var i = 0; i < 8; i++) sum += Number(n.charAt(2 + i)) * w[i]
    var c = 11 - sum % 11
    if (c === 10) c = 0
    if (c === 11) c = 5
    return c === Number(n.charAt(10))
}
var TRACK_WORDS = /track|tracking|shipment|parcel|package|suivi|colis|envoi|livraison|sendung|paket|lieferung|vận đơn|van don|mã đơn|bưu kiện|ups|fedex|dhl|colissimo|chronopost|la poste/i
function carrierFromWords(t) {
    if (/chronopost/i.test(t)) return "chronopost"
    if (/colissimo/i.test(t)) return "colissimo"
    if (/la poste|laposte/i.test(t)) return "laposte"
    if (/\bdhl\b/i.test(t)) return "dhl"
    if (/fedex/i.test(t)) return "fedex"
    if (/\bups\b/i.test(t)) return "ups"
    return ""
}
function trackingKind(t) {
    if (t.length > 3000) return null
    var up = t.toUpperCase()
    var found = null
    var m = /\b1Z[0-9A-Z]{16}\b/.exec(up)
    if (m && upsValid(m[0])) found = { carrier: "ups", number: m[0] }
    if (!found) {
        var re = /\b([A-Z]{2})(\d{9})([A-Z]{2})\b/g, s
        while ((s = re.exec(up)) !== null) {
            if (!s10Valid(s[0])) continue
            var c = carrierFromWords(t)
            if (!c) c = s[3] === "FR" ? (/^[EX]/.test(s[1]) ? "chronopost" : "laposte") : s[3] === "DE" ? "dhl" : "other"
            found = { carrier: c, number: s[0] }
            break
        }
    }
    if (!found) {
        m = /\b\d[A-Z]\d{11}\b/.exec(up)
        if (m) found = { carrier: carrierFromWords(t) || "colissimo", number: m[0] }
    }
    if (!found) {
        m = /\b(JJD\d{10,20}|JVGL\d{8,20}|00340\d{15})\b/.exec(up)
        if (m) found = { carrier: "dhl", number: m[0] }
    }
    // Bare digits only with the carrier or a tracking word around them
    // (twelve digits alone could be anything).
    if (!found && TRACK_WORDS.test(t)) {
        var who = carrierFromWords(t)
        m = who === "dhl" ? /\b(\d{10}|\d{12}|\d{20})\b/.exec(up)
            : who === "fedex" ? /\b(\d{12}|\d{15}|\d{20}|\d{22})\b/.exec(up)
            : /\b(?=[A-Z0-9]{10,30}\b)(?=(?:[A-Z]*\d){8})[A-Z0-9]{10,30}\b/.exec(up)
        if (m) found = { carrier: who || "other", number: m[0] }
    }
    if (!found) return null
    var info = CARRIERS[found.carrier] || CARRIERS.other
    return { kind: "tracking", detail: info.name, number: found.number,
             actions: [{ id: "track", model: false, url: info.url + encodeURIComponent(found.number), carrier: info.name }] }
}

// ── Phone numbers ─────────────────────────────────────────────────────────
var DATEISH = /^\d{4}-\d{1,2}-\d{1,2}$|^\d{1,2}[\/.\-]\d{1,2}[\/.\-]\d{2,4}$/
function phoneIn(s, whole) {
    var re = whole ? /^(?:tel:|téléphone\s*:?\s*|tél\.?\s*:?\s*|phone\s*:?\s*|tel\.?\s*:?\s*)?(\+?[\d][\d\s().\-\/]{5,22}\d)$/i
        : /(?:^|[^\w+])(\+\d[\d\s().\-]{6,20}\d|0\d(?:[\s.\-]?\d\d){4}|00\d[\d\s.\-]{7,18}\d|\(\d{3}\)\s?\d{3}-\d{4})(?![\w])/
    var m = re.exec(s)
    if (!m) return ""
    var raw = m[1].trim()
    if (DATEISH.test(raw)) return ""
    var digits = raw.replace(/\D/g, "")
    if (digits.length < 8 || digits.length > 15) return ""
    var plus = /^\+/.test(raw) || /^00/.test(raw)
    var separated = /[\s.\-()\/]/.test(raw)
    if (!plus && !/^0/.test(raw) && !(separated && digits.length >= 9) && !/^\(\d{3}\)/.test(raw)) return ""
    // Groups like a time or a version (12.30, 1.2.3) aren't phones.
    if (/^\d{1,2}[.:]\d{2}$/.test(raw)) return ""
    return (plus ? "+" : "") + (/^00/.test(raw) ? digits.slice(2) : digits)
}
// `whole`: the text is the number; else one inside a short text.
function phoneKind(t, whole) {
    var s = t.trim()
    var n = whole ? (s.length <= 40 ? phoneIn(s, true) : "")
        : (s.length <= 160 && s.split("\n").length <= 3 && phoneIn(s, true) === "" ? phoneIn(s, false) : "")
    if (!n) return null
    return { kind: "phone", detail: n, number: n,
             actions: [{ id: "call", model: false, number: n }, { id: "text", model: false, number: n }] }
}

// ── Errors and code ───────────────────────────────────────────────────────
// ContextTriggers.errorLine, and the single lines that are an error alone.
var ERROR_LINE = /\b(error|exception|traceback|panic|failed|fatal)\b|^\s*at\s+\S.*:\d+/i
var ERROR_ONE = /Traceback \(most recent call last\)|^\s*(error|fatal|panic|erreur|fehler)(\[[\w\-]+\])?:|^\s*\w*(Error|Exception)(: | in )|Exception in thread|segmentation fault|command not found|undefined reference|no such file or directory|npm ERR!|error\[E\d+\]|^E\d{4}:|exit (code|status) [1-9]|Uncaught \w*Error|^\s*thread '.+' panicked|cannot find module|permission denied|nicht gefunden|introuvable|commande introuvable/im
function errorKind(t) {
    var lines = t.split("\n")
    var hits = 0
    for (var i = 0; i < lines.length && i < 400; i++) if (ERROR_LINE.test(lines[i])) hits++
    if (hits < 2 && !ERROR_ONE.test(t)) return null
    // A sentence about an error ("the build failed yesterday") isn't one.
    if (lines.length === 1 && hits < 2 && t.length > 400) return null
    var first = ""
    for (var j = 0; j < lines.length; j++)
        if (ERROR_LINE.test(lines[j]) || ERROR_ONE.test(lines[j])) { first = lines[j].trim(); break }
    return { kind: "error", detail: first.slice(0, 80),
             actions: [{ id: "explain", model: true }, { id: "fixError", model: true }] }
}
var CODE_SIGNS = [
    /[;{}]\s*$/, /^\s*(def|class|function|fn|func|import|from|#include|const|let|var|public|private|protected|return|package|use|struct|enum|impl|interface|type|module|export)\b/,
    /=>|->|::|:=/, /^( {2,}|\t)\S/, /<\/?[a-z][\w\-]*(\s[^>]*)?>/i, /^\s*[$#] [a-z]/, /\w{1,60}\([^)]{0,200}\)\s*[{;:]?\s*$/,
    /(==|!=|&&|\|\||\+=|<=|>=)/, /^\s*(if|for|while|elif|else|switch|case|try|catch|except)\b.*[:{(]\s*$/, /^\s*(\/\/|#!|\/\*|\*\/|--\s)/,
    /\$\{?[A-Za-z_]{1,40}\}?/, /^\s*[\w.]{1,80}\s*=\s*\S/,
    /^\s*(SELECT|INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|WITH|WHERE|GROUP BY|ORDER BY|FROM|JOIN|LEFT JOIN|VALUES|SET)\b/
]
var SHELL_CMD = /^\s*(sudo |nix |nix-\w+ |git |docker |podman |kubectl |helm |npm |pnpm |yarn |cargo |go |systemctl |journalctl |ls |cd |grep |rg |sed |awk |curl |wget |ssh |scp |chmod |chown |mkdir |rm |cp |mv |tar |python3? |pip |make |cmake |colmena |home-manager )\S/
function codeKind(t) {
    var lines = t.split("\n").filter(function (l) { return l.trim().length > 0 })
    if (lines.length === 0 || lines.length > 400) return null
    // One huge line (minified, a blob): not something to explain.
    for (var q = 0; q < lines.length; q++) if (lines[q].length > 2000) return null
    if (lines.length === 1) {
        var l = lines[0]
        var one = 0
        for (var i = 0; i < CODE_SIGNS.length; i++) if (CODE_SIGNS[i].test(l)) one++
        if (!(SHELL_CMD.test(l) && /\s-{1,2}\w|\s\S+\/|\|/.test(l)) && one < 3) return null
    } else {
        var signed = 0
        for (var k = 0; k < lines.length; k++) {
            for (var j = 0; j < CODE_SIGNS.length; j++) if (CODE_SIGNS[j].test(lines[k])) { signed++; break }
        }
        // Prose has full sentences; code mostly signs.
        if (signed < 2 || signed < lines.length * 0.5) return null
    }
    return { kind: "code", detail: "", actions: [{ id: "explain", model: true }] }
}

// ── Dates and times (en, fr, de, vi) ──────────────────────────────────────
var MONTHS = [
    ["january", "jan", "janvier", "janv", "januar", "jänner", "jaenner"],
    ["february", "feb", "février", "fevrier", "févr", "fevr", "februar"],
    ["march", "mars", "märz", "maerz", "mär"],
    ["april", "apr", "avril", "avr"],
    ["may", "mai"],
    ["june", "jun", "juin", "juni"],
    ["july", "jul", "juillet", "juil", "juli"],
    ["august", "aug", "août", "aout"],
    ["september", "sep", "sept", "septembre"],
    ["october", "oct", "octobre", "oktober", "okt"],
    ["november", "nov", "novembre"],
    ["december", "dec", "décembre", "decembre", "déc", "dezember", "dez"]
]
var MONTH_INDEX = {}
var MONTH_ALT = []
;(function () {
    for (var i = 0; i < MONTHS.length; i++)
        for (var j = 0; j < MONTHS[i].length; j++) {
            MONTH_INDEX[MONTHS[i][j]] = i
            MONTH_ALT.push(MONTHS[i][j])
        }
    // Longest first: "june" before "jun".
    MONTH_ALT.sort(function (a, b) { return b.length - a.length })
})()
var MONTH_RE = "(" + MONTH_ALT.join("|") + ")\\.?"
// Sunday first (getDay()).
var WEEKDAYS = [
    ["sunday", "dimanche", "sonntag", "chủ nhật", "chu nhat"],
    ["monday", "lundi", "montag", "thứ hai", "thứ 2", "thu hai"],
    ["tuesday", "mardi", "dienstag", "thứ ba", "thứ 3", "thu ba"],
    ["wednesday", "mercredi", "mittwoch", "thứ tư", "thứ 4", "thu tu"],
    ["thursday", "jeudi", "donnerstag", "thứ năm", "thứ 5", "thu nam"],
    ["friday", "vendredi", "freitag", "thứ sáu", "thứ 6", "thu sau"],
    ["saturday", "samedi", "samstag", "thứ bảy", "thứ 7", "thu bay"]
]

function pad2(n) { return (n < 10 ? "0" : "") + n }
function validDay(y, m, d) {
    var x = new Date(y, m, d)
    return x.getFullYear() === y && x.getMonth() === m && x.getDate() === d
}

// The time said in `s`: {h, m, start, end} or null.
function findTime(s) {
    var c, h, mi, mer
    // 3pm, 3:30 pm, 3.30pm
    c = /\b(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)/i.exec(s)
    if (c) {
        h = Number(c[1]); mi = Number(c[2] || 0); mer = c[3].toLowerCase().charAt(0)
        if (h >= 1 && h <= 12 && mi < 60) {
            if (mer === "p" && h < 12) h += 12
            if (mer === "a" && h === 12) h = 0
            return { h: h, m: mi, start: c.index, end: c.index + c[0].length }
        }
    }
    // 15 Uhr, 15.30 Uhr, 15:30 Uhr
    c = /\b(\d{1,2})(?:[:.](\d{2}))?\s*uhr\b/i.exec(s)
    if (c && Number(c[1]) < 24) return { h: Number(c[1]), m: Number(c[2] || 0), start: c.index, end: c.index + c[0].length }
    // 3 giờ chiều, 15 giờ 30, 9g sáng (Vietnamese; "giờ" isn't an ASCII word: no \b after it)
    c = /\b(\d{1,2})\s*(?:giờ|gio\b)(?:\s*(\d{1,2})(?:\s*phút)?)?(?:\s*(sáng|sang|trưa|trua|chiều|chieu|tối|toi|đêm))?/i.exec(s)
    if (c && Number(c[1]) < 24) {
        h = Number(c[1]); mi = Number(c[2] || 0)
        var p = (c[3] || "").toLowerCase()
        if (/^(chiều|chieu|tối|toi)/.test(p) && h < 12) h += 12
        if (mi < 60) return { h: h, m: mi, start: c.index, end: c.index + c[0].length }
    }
    // 14h, 14h30, 14 h 30 (French)
    c = /\b(\d{1,2})\s?h\s?(\d{2})?\b/i.exec(s)
    if (c && Number(c[1]) < 24 && Number(c[2] || 0) < 60) return { h: Number(c[1]), m: Number(c[2] || 0), start: c.index, end: c.index + c[0].length }
    // 15:30 (24 h)
    c = /\b([01]?\d|2[0-3]):([0-5]\d)\b/.exec(s)
    if (c) return { h: Number(c[1]), m: Number(c[2]), start: c.index, end: c.index + c[0].length }
    c = /\b(noon|midday|midi|mittag|mittags)\b|\btrưa\b/i.exec(s)
    if (c) return { h: 12, m: 0, start: c.index, end: c.index + c[0].length }
    return null
}

// Time zones said after a time ("9:00 PM ET", "15:00 CET", "3pm (PT)",
// "10h UTC+7"): fixed offsets in minutes east of UTC, or a rule with its
// standard offset (us: second Sunday of March to first Sunday of November,
// 2:00 local; eu: last Sunday of March to last Sunday of October, 1:00 UTC).
// Abbreviations only in capitals: "et" is French for "and".
var ZONES = {
    ET: { std: -300, rule: "us" }, EST: { fixed: -300 }, EDT: { fixed: -240 },
    CT: { std: -360, rule: "us" }, CST: { fixed: -360 }, CDT: { fixed: -300 },
    MT: { std: -420, rule: "us" }, MST: { fixed: -420 }, MDT: { fixed: -360 },
    PT: { std: -480, rule: "us" }, PST: { fixed: -480 }, PDT: { fixed: -420 },
    AKST: { fixed: -540 }, AKDT: { fixed: -480 }, HST: { fixed: -600 },
    UTC: { fixed: 0 }, GMT: { fixed: 0 }, BST: { fixed: 60 },
    WET: { std: 0, rule: "eu" }, WEST: { fixed: 60 },
    CET: { std: 60, rule: "eu" }, CEST: { fixed: 120 },
    EET: { std: 120, rule: "eu" }, EEST: { fixed: 180 },
    IST: { fixed: 330 }, ICT: { fixed: 420 }, SGT: { fixed: 480 }, HKT: { fixed: 480 },
    JST: { fixed: 540 }, KST: { fixed: 540 }, AEST: { fixed: 600 }, AEDT: { fixed: 660 },
    NZST: { fixed: 720 }, NZDT: { fixed: 780 }
}
var ZONE_NAMES = { eastern: "ET", central: "CT", mountain: "MT", pacific: "PT" }
var ZONE_RE = new RegExp("^\\s*[(,]?\\s*(?:(UTC|GMT)\\s*([+\\-−])\\s*(\\d{1,2})(?::?(\\d{2}))?|("
    + Object.keys(ZONES).sort(function (a, b) { return b.length - a.length }).join("|")
    + ")(?![A-Za-z])|(?:(eastern|central|mountain|pacific)(?:\\s+(standard|daylight))?\\s+time))\\)?", "i")
// The zone right after a time: {label, offset(y, mo, d, h, m) → minutes, end} or null.
function zoneAfter(s, pos) {
    var c = ZONE_RE.exec(s.slice(pos))
    if (!c) return null
    var z, label
    if (c[1]) {
        if (c[1] !== c[1].toUpperCase()) return null
        var off = (Number(c[3]) * 60 + Number(c[4] || 0)) * (c[2] === "+" ? 1 : -1)
        if (Math.abs(off) > 14 * 60) return null
        z = { fixed: off }; label = c[0].replace(/^[\s(,]+|\)$/g, "").trim()
    } else if (c[5]) {
        if (c[5] !== c[5].toUpperCase()) return null
        z = ZONES[c[5]]; label = c[5]
    } else {
        label = ZONE_NAMES[c[6].toLowerCase()]
        var std = ZONES[label].std
        z = c[7] ? { fixed: std + (c[7].toLowerCase() === "daylight" ? 60 : 0) } : ZONES[label]
        label = c[0].replace(/^[\s(,]+|\)$/g, "").trim()
    }
    return { label: label, end: pos + c[0].length, offset: function (y, mo, d, h, m) { return zoneOffset(z, y, mo, d, h, m) } }
}
function sundayOf(y, mo, n) {
    // n-th Sunday (1-based) of the month, or the last one for n = -1: the day.
    if (n > 0) {
        var first = new Date(Date.UTC(y, mo, 1)).getUTCDay()
        return 1 + (7 - first) % 7 + (n - 1) * 7
    }
    var lastDay = new Date(Date.UTC(y, mo + 1, 0))
    return lastDay.getUTCDate() - lastDay.getUTCDay()
}
function zoneOffset(z, y, mo, d, h, m) {
    if (z.fixed !== undefined) return z.fixed
    var wall = Date.UTC(y, mo, d, h, m)
    if (z.rule === "us") {
        var a = Date.UTC(y, 2, sundayOf(y, 2, 2), 2), b = Date.UTC(y, 10, sundayOf(y, 10, 1), 2)
        return z.std + (wall >= a && wall < b ? 60 : 0)
    }
    var utc = wall - z.std * 60000
    var s0 = Date.UTC(y, 2, sundayOf(y, 2, -1), 1), s1 = Date.UTC(y, 9, sundayOf(y, 9, -1), 1)
    return z.std + (utc >= s0 && utc < s1 ? 60 : 0)
}

// The day said in `s`: {y, mo, d, start, end} or null. `now` a Date.
function findDay(s, now, lang) {
    var low = s.toLowerCase()
    var c, y, mo, d
    var today = new Date(now.getFullYear(), now.getMonth(), now.getDate())
    function plus(n) {
        var x = new Date(today.getFullYear(), today.getMonth(), today.getDate() + n)
        return { y: x.getFullYear(), mo: x.getMonth(), d: x.getDate() }
    }
    function at(r, m) { r.start = m.index; r.end = m.index + m[0].length; return r }
    function nextYearIfPast(r) {
        if (r.explicitYear) return r
        var x = new Date(r.y, r.mo, r.d)
        if (x.getTime() < today.getTime() - 86400000) r.y += 1
        return r
    }
    // 2026-11-12
    c = /\b(\d{4})-(\d{1,2})-(\d{1,2})\b/.exec(low)
    if (c && validDay(Number(c[1]), Number(c[2]) - 1, Number(c[3]))) return at({ y: Number(c[1]), mo: Number(c[2]) - 1, d: Number(c[3]) }, c)
    // 12 novembre (2026), 12. November, 12th of November, 12 de noviembre
    c = new RegExp("\\b(\\d{1,2})(?:st|nd|rd|th|er|e|\\.)?\\s+(?:of\\s+|de\\s+)?" + MONTH_RE + "(?:\\s+(\\d{4}))?(?![a-zà-ÿ])", "i").exec(low)
    if (c) {
        d = Number(c[1]); mo = MONTH_INDEX[c[2]]; y = c[3] ? Number(c[3]) : now.getFullYear()
        if (validDay(y, mo, d)) return at(nextYearIfPast({ y: y, mo: mo, d: d, explicitYear: !!c[3] }), c)
    }
    // November 12(th)(, 2026); "may 5" not after a pronoun ("you may 5…"),
    // and never "mai" first (Vietnamese "mai 9 giờ" is tomorrow at 9).
    c = new RegExp("(?:^|[^a-zà-ÿ])" + MONTH_RE + "\\s+(\\d{1,2})(?:st|nd|rd|th)?(?![\\d:h])(?:,?\\s+(\\d{4}))?", "i").exec(low)
    var verbLike = c && (c[1] === "may" || c[1] === "march")
        && !/^[A-Z]/.test(s.slice(c.index, c.index + c[0].length).replace(/^[^A-Za-z]+/, ""))
    if (c && c[1] !== "mai" && !verbLike) {
        mo = MONTH_INDEX[c[1]]; d = Number(c[2]); y = c[3] ? Number(c[3]) : now.getFullYear()
        if (mo !== undefined && validDay(y, mo, d))
            return nextYearIfPast({ y: y, mo: mo, d: d, explicitYear: !!c[3], start: c.index, end: c.index + c[0].length })
    }
    // ngày 12 tháng 11 (năm 2026)
    c = /(?:ngày\s*)?(\d{1,2})\s*tháng\s*(\d{1,2})(?:\s*(?:năm|,)?\s*(\d{4}))?/i.exec(low)
    if (c) {
        d = Number(c[1]); mo = Number(c[2]) - 1; y = c[3] ? Number(c[3]) : now.getFullYear()
        if (validDay(y, mo, d)) return at(nextYearIfPast({ y: y, mo: mo, d: d, explicitYear: !!c[3] }), c)
    }
    // 12/11/2026, 12.11.2026, 12.11. (day first; month first in English
    // when the day can't be first)
    c = /\b(\d{1,2})([\/.])(\d{1,2})(?:\2(\d{4}|\d{2})\b|(\.))?(?![\d\/])/.exec(low)
    if (c && (c[4] || c[5] || c[2] === "/")) {
        var a = Number(c[1]), b = Number(c[3])
        var monthFirst = (lang === "en" && b <= 31 && a <= 12 && c[2] === "/") || b > 12
        d = monthFirst ? b : a; mo = (monthFirst ? a : b) - 1
        y = c[4] ? (c[4].length === 2 ? 2000 + Number(c[4]) : Number(c[4])) : now.getFullYear()
        // A bare "3/4" is a fraction unless a time or a day word goes with it.
        var dayWord = /\b(on|le|du|au|am|vom|bis|ngày|date|datum)\s*$/i.test(low.slice(0, c.index)) || findTime(s) !== null
        if ((c[4] || c[5] || dayWord) && mo >= 0 && validDay(y, mo, d))
            return at(nextYearIfPast({ y: y, mo: mo, d: d, explicitYear: !!c[4] }), c)
    }
    // Relative days.
    c = /\b(day after tomorrow|apres-demain|uebermorgen)\b|après-demain|übermorgen|ngày kia|ngày mốt/i.exec(low)
    if (c) return at(plus(2), c)
    c = /\b(tomorrow|demain)\b|ngày mai|\bmai\s+(?:lúc|sáng|chiều|tối)/i.exec(low)
    if (c) return at(plus(1), c)
    c = /\bmorgen\b/.exec(low)
    if (c && !/guten\s+morgen|\bam\s+morgen|\bheute\s+morgen/.test(low)) return at(plus(1), c)
    c = /\b(today|tonight|this (evening|afternoon|morning)|aujourd'hui|aujourd’hui|ce soir|cet après-midi|ce matin|heute)\b|hôm nay|tối nay|chiều nay|sáng nay/i.exec(low)
    if (c) {
        var r1 = at(plus(0), c)
        if (/tonight|this evening|ce soir|tối nay|heute abend/.test(c[0] + low.slice(c.index, c.index + 14))) r1.evening = true
        return r1
    }
    // in 3 days, dans 3 jours, in 3 Tagen, 3 ngày nữa
    c = /\b(?:in|dans)\s+(\d{1,2})\s+(days?|jours?|tagen)\b|\b(\d{1,2})\s+ngày\s+nữa/i.exec(low)
    if (c) return at(plus(Number(c[1] || c[3])), c)
    // A weekday, the next one (next / prochain / nächsten: after today;
    // "tuần sau" / "next week": in the week after).
    for (var wd = 0; wd < 7; wd++) {
        for (var k = 0; k < WEEKDAYS[wd].length; k++) {
            var name = WEEKDAYS[wd][k]
            var re = /^[a-z]/.test(name) && !/ /.test(name) ? new RegExp("\\b" + name + "s?\\b", "i") : new RegExp(name, "i")
            c = re.exec(low)
            if (!c) continue
            var around = low.slice(Math.max(0, c.index - 12), c.index + c[0].length + 16)
            var delta = (wd - today.getDay() + 7) % 7
            var sameDay = delta === 0
            if (delta === 0) delta = 7
            if (/next week|semaine prochaine|nächste woche|tuần sau|tuần tới/.test(low) && delta < 7
                && today.getDay() !== 0 && wd > today.getDay()) delta += 7
            var r2 = plus(delta)
            r2.start = c.index; r2.end = c.index + c[0].length
            r2.sameDay = sameDay
            // "next Tuesday", "mardi prochain", "nächsten Dienstag": the span with its word.
            var mod = /\b(next|this|coming|prochain|prochaine|nächsten|nächste|kommenden|diesen)\b/i.exec(around)
            r2.modified = !!mod
            if (mod) {
                var mi2 = low.indexOf(mod[0], Math.max(0, c.index - 12))
                if (mi2 >= 0) { r2.start = Math.min(r2.start, mi2); r2.end = Math.max(r2.end, mi2 + mod[0].length) }
            }
            return r2
        }
    }
    return null
}

// Words that only joined the date to the rest, cut from the title.
var JOINERS = /(?:^|\s)(on|at|by|from|le|à|a|au|du|am|um|ab|lúc|luc|vào|vao|ngày|next|this|coming|prochain|prochaine|nächsten|nächste|kommenden|tuần sau)\s*$/i
function dateKind(t, now, lang) {
    if (t.length > 400 || t.split("\n").length > 6) return null
    var day = findDay(t, now, lang)
    var time = findTime(t)
    // A time alone ("at 3pm") isn't enough to make an event of.
    if (!day) return null
    var h = time ? time.h : (day.evening ? 20 : 0), m = time ? time.m : 0
    var when = new Date(day.y, day.mo, day.d, h, m, 0, 0)
    // "9:00 PM ET": that time where it was said, put in the local time.
    var zone = time ? zoneAfter(t, time.end) : null
    var said = ""
    if (zone) {
        when = new Date(Date.UTC(day.y, day.mo, day.d, h, m) - zone.offset(day.y, day.mo, day.d, h, m) * 60000)
        said = t.slice(time.start, time.end).trim() + " " + zone.label
        time.end = zone.end
    }
    // "Monday 5pm" said on a Monday morning: today, not next week.
    if (day.sameDay && !day.modified && time && !zone) {
        var todayAt = new Date(now.getFullYear(), now.getMonth(), now.getDate(), h, m, 0, 0)
        if (todayAt.getTime() > now.getTime()) when = todayAt
    }
    // The title: the text without the date and the time, their joining words.
    var spans = [[day.start, day.end]]
    if (time) spans.push([time.start, time.end])
    spans.sort(function (a, b) { return b[0] - a[0] })
    var title = t
    for (var i = 0; i < spans.length; i++) {
        var before = title.slice(0, spans[i][0]).replace(JOINERS, "")
        title = before + " " + title.slice(spans[i][1])
    }
    title = title.replace(/\s+/g, " ").replace(/^[\s,.;:–—\-]+|[\s,.;:–—\-]+$/g, "").replace(JOINERS, "").trim()
    if (title.length > 80) title = title.slice(0, 79).replace(/\s+\S*$/, "") + "…"
    var addr = addressIn(t)
    return { kind: "date", detail: "", when: when.getTime(), hasTime: !!time || !!day.evening, title: title, location: addr, said: said,
             actions: [{ id: "calendar", model: false, when: when.getTime(), hasTime: !!time || !!day.evening, title: title, location: addr }] }
}

// ── Postal addresses ──────────────────────────────────────────────────────
var STREET_FR = /\b\d{1,4}\s*(?:bis|ter)?,?\s+(?:rue|avenue|av\.?|boulevard|bd|place|chemin|allée|allee|impasse|quai|route|cours|square|passage|voie|faubourg|rte|résidence)\s+[^\n,;]{2,60}/i
var STREET_DE = /[A-Za-zÄÖÜäöüß.\-]{2,40}(?:straße|strasse|str\.|weg|gasse|platz|allee|ring|damm|ufer|chaussee)\s+\d{1,4}\s?[a-z]?\b/i
var STREET_EN = /\b\d{1,5}[A-Za-z]?\s+(?:[A-Za-z0-9.'\-]+\s+){1,4}(?:street|st|avenue|ave|road|rd|boulevard|blvd|lane|ln|drive|dr|way|court|ct|place|pl|terrace|parkway|pkwy|square|sq|highway|hwy)\b\.?/i
var STREET_VI = /(?:số\s*)?\b\d{1,4}[A-Za-z]?(?:\/\d+)*\s+(?:đường|phố|ngõ|hẻm|ngách)\s+[^\n,;]{2,40}/i
var POSTCODE = /\b\d{5}\s+[A-Za-zÀ-ÿ][A-Za-zÀ-ÿ'\- ]{1,40}|\b[A-Z]{2}\s+\d{5}(?:-\d{4})?\b|\b[A-Z]{1,2}\d[A-Z\d]?\s*\d[A-Z]{2}\b/
var VI_AREAS = /(phường|quận|huyện|thành phố|tp\.|tỉnh|thị xã)/gi
// The address in `t` (its street through its city), or "".
function addressIn(t) {
    if (t.length > 400) return ""
    var flat = t.replace(/\s*\n\s*/g, ", ")
    var m = STREET_FR.exec(flat) || STREET_DE.exec(flat) || STREET_EN.exec(flat) || STREET_VI.exec(flat)
    var areas = (flat.match(VI_AREAS) || []).length
    if (!m && !(areas >= 2 && /\d/.test(flat))) return ""
    if (!m) return flat.trim().slice(0, 200)
    var start = m.index, end = m.index + m[0].length
    // The postcode and city after it, when it goes on with them.
    var rest = flat.slice(end, end + 80)
    var p = POSTCODE.exec(rest)
    if (p && p.index < 30) end = end + p.index + p[0].length
    else if (areas >= 1) end = Math.min(flat.length, end + 80)
    var out = flat.slice(start, end).replace(/[\s,;.]+$/, "").trim()
    // No postcode nor city: only a named street ("12 rue de Rivoli",
    // "Hauptstraße 5"; not "3 place settings", "String 5"), the text about
    // nothing else.
    if (!p && !areas) {
        var named = /^\d/.test(out) ? /\s[A-ZÀ-Ý]/.test(out.replace(/^\S+\s+\S+/, "")) : /^[A-ZÄÖÜ]/.test(out) && !/(ring|weg)\s/i.test(out)
        if (!named || flat.trim().length > out.length + 40) return ""
    }
    return out.slice(0, 200)
}
function addressKind(t) {
    var a = addressIn(t)
    if (!a) return null
    var q = encodeURIComponent(a)
    return { kind: "address", detail: a.slice(0, 60), address: a,
             actions: [{ id: "directions", model: false, url: "https://www.google.com/maps/dir/?api=1&destination=" + q },
                       { id: "map", model: false, url: "https://www.google.com/maps/search/?api=1&query=" + q }] }
}

// ── Amounts ───────────────────────────────────────────────────────────────
var CURRENCY_SIGNS = { "€": "EUR", "$": "USD", "£": "GBP", "¥": "JPY", "₫": "VND", "₩": "KRW", "₹": "INR", "chf": "CHF" }
var CURRENCY_WORDS = /^(eur|euros?|usd|dollars?|us\$|gbp|pounds?|chf|jpy|yen|vnd|đồng|dong|vnđ|cad|aud|cny|yuan|rmb|krw|inr|sek|nok|dkk|pln|czk)$/i
function currencyOf(w) {
    w = w.toLowerCase()
    if (CURRENCY_SIGNS[w]) return CURRENCY_SIGNS[w]
    if (/^euros?$/.test(w)) return "EUR"
    if (/^(dollars?|us\$)$/.test(w)) return "USD"
    if (/^pounds?$/.test(w)) return "GBP"
    if (/^(yen)$/.test(w)) return "JPY"
    if (/^(đồng|dong|vnđ)$/.test(w)) return "VND"
    if (/^(yuan|rmb)$/.test(w)) return "CNY"
    return w.toUpperCase()
}
// "1.299,99" / "1,299.99" / "1 299,99" / "500.000" (VND) as a number.
function amountValue(s, cur) {
    s = s.replace(/[\s' ]/g, "")
    var dot = s.lastIndexOf("."), comma = s.lastIndexOf(",")
    if (dot >= 0 && comma >= 0) {
        var dec = dot > comma ? "." : ","
        s = s.split(dec === "." ? "," : ".").join("").replace(",", ".")
    } else if (dot >= 0 || comma >= 0) {
        var sep = dot >= 0 ? "." : ","
        var parts = s.split(sep)
        var last = parts[parts.length - 1]
        if (parts.length > 2 || (last.length === 3 && (cur === "VND" || cur === "JPY" || cur === "KRW"))) s = parts.join("")
        else if (last.length === 3 && sep === ",") s = parts.join("")
        else s = parts.join(".")
    }
    var v = Number(s)
    return isNaN(v) ? null : v
}
var AMOUNT_RE = /(?:^|[\s(])(?:([€$£¥₫₩₹]|US\$|CHF)\s?(\d[\d\s.,' ]*\d|\d)|(\d[\d\s.,' ]*\d|\d)\s?([€$£¥₫₩₹]|[A-Za-zđồ]{2,7}))(?=$|[\s).,;!?])/
function amountKind(t, home) {
    if (t.length > 80) return null
    var re = new RegExp(AMOUNT_RE.source, "g"), m, sign = "", num = ""
    while ((m = re.exec(t.trim())) !== null) {
        var sg = m[1] || m[4]
        if (m[1] || /^[€$£¥₫₩₹]$/.test(sg) || CURRENCY_WORDS.test(sg)) { sign = sg; num = m[2] || m[3]; break }
        re.lastIndex = m.index + 1
    }
    if (!sign) return null
    var cur = currencyOf(sign)
    var v = amountValue(num, cur)
    if (v === null || v <= 0) return null
    var to = home && home !== cur ? home : (cur === "USD" ? "EUR" : "USD")
    var q = encodeURIComponent(v + " " + cur + " in " + to)
    return { kind: "amount", detail: v + " " + cur, amount: v, currency: cur,
             actions: [{ id: "convert", model: false, from: cur, to: to, url: "https://www.google.com/search?q=" + q }] }
}

// ── Languages ─────────────────────────────────────────────────────────────
var STOPWORDS = {
    en: "the and is are of to in that it you for with this was have not be on at we they but from will would can your our what there".split(" "),
    fr: "le la les des est et un une du que qui pas pour dans sur avec ce cette il elle nous vous sont au aux mais ne plus je à été être très ça".split(" "),
    de: "der die das und ist nicht ein eine zu den dem mit sich auf für von ich sie es wir auch aber wird sind bei nach noch oder wie über".split(" "),
    es: "el los las y es que en un una por para con no se del al lo como pero más su está son muy yo".split(" "),
    it: "il lo gli e è di che non un una per con del della sono ma come anche questo alla nel ho sei".split(" "),
    pt: "o os as e é que não um uma para com do da dos em se mas muito está são você eu".split(" "),
    nl: "de het een en is van niet dat ik je met op voor zijn maar ook er wat naar aan bij".split(" "),
    vi: "và của là không có được những cho này với các một người trong đã sẽ rất bạn tôi anh em".split(" ")
}
var VI_LETTERS = /[ăơưđạảấầẩẫậắằẳẵặẹẻẽếềểễệỉịọỏốồổỗộớờởỡợụủứừửữựỳỵỷỹ]/gi
// The language of `t` ("" when it can't tell).
function languageOf(t) {
    var s = t.slice(0, 4000)
    var letters = s.replace(/[\s\d.,;:!?()"'«»„“”’\-—–\/\[\]{}@#&*+=_<>|~`^%$€£]/g, "").length
    if (letters < 6) return ""
    function share(re) { return (s.match(re) || []).length / letters }
    if (share(/[\u3040-\u30ff]/g) > 0.1) return "ja"
    if (share(/[\u4e00-\u9fff]/g) > 0.3) return "zh"
    if (share(/[\uac00-\ud7af]/g) > 0.3) return "ko"
    if (share(/[\u0400-\u04ff]/g) > 0.4) return "ru"
    if (share(/[\u0600-\u06ff]/g) > 0.4) return "ar"
    if (share(/[\u0590-\u05ff]/g) > 0.4) return "he"
    if (share(/[\u0370-\u03ff]/g) > 0.4) return "el"
    if (share(/[\u0e00-\u0e7f]/g) > 0.4) return "th"
    if (share(/[\u0900-\u097f]/g) > 0.4) return "hi"
    var words = s.toLowerCase().split(/[\s.,;:!?()"«»„“”’'\-—–\/\[\]{}0-9]+/).filter(function (w) { return w.length > 0 })
    if (words.length < 4) return ""
    if ((s.match(VI_LETTERS) || []).length >= 2) return "vi"
    var best = "", bestN = 0, second = 0
    for (var lang in STOPWORDS) {
        var set = STOPWORDS[lang], n = 0
        for (var i = 0; i < words.length; i++) if (set.indexOf(words[i]) >= 0) n++
        if (n > bestN) { second = bestN; bestN = n; best = lang }
        else if (n > second) second = n
    }
    // Clearly one: two stopwords at least, ahead of the next language.
    if (bestN < 2 || bestN < second * 1.5 || bestN < words.length * 0.08) return ""
    return best
}
function languageKind(t, lang, known) {
    if (t.length < 15) return null
    var l = languageOf(t)
    if (!l || l === lang || (known || []).indexOf(l) >= 0) return null
    var actions = [{ id: "translate", model: true, from: l, to: lang }]
    if (t.length > 600) actions.push({ id: "summarize", model: true })
    return { kind: "language", detail: l, language: l, actions: actions }
}

// ── A long paragraph ──────────────────────────────────────────────────────
function paragraphKind(t) {
    if (t.length < 320) return null
    var words = t.split(/\s+/).length
    var sentences = (t.match(/[.!?…。](\s|$)/g) || []).length
    var letters = (t.match(/[A-Za-zÀ-ÿĀ-ỹ]/g) || []).length
    if (words < 50 || sentences < 2 || letters < t.length * 0.6) return null
    return { kind: "paragraph", detail: words + " words", words: words,
             actions: [{ id: "summarize", model: true }, { id: "rewrite", model: true }] }
}

var HOME_CURRENCY = { en: "USD", fr: "EUR", de: "EUR", vi: "VND" }

// The kinds of `text`, best first, or a secret: {secret, why, candidates}.
function classify(text, opts) {
    opts = opts || {}
    var t = String(text === undefined || text === null ? "" : text).replace(/\r\n?/g, "\n")
    var trimmed = t.trim()
    var out = { secret: false, why: "", candidates: [] }
    if (trimmed.length < 3) return out
    if (trimmed.length > 20000) { out.why = "too long"; return out }
    var why = secretWhy(trimmed, opts.app || "")
    if (why) { out.secret = true; out.why = why; return out }
    var now = opts.now ? new Date(opts.now) : new Date()
    var lang = String(opts.lang || "en").slice(0, 2)
    var home = opts.currency || HOME_CURRENCY[lang] || "EUR"
    var c = []
    var single = !/\s/.test(trimmed)
    if (single) {
        var u = urlKind(trimmed)
        if (u) c.push(u)
        var e = emailOf(trimmed)
        if (e) c.push({ kind: "email", detail: e, address: e, actions: [{ id: "mail", model: false, address: e }] })
    } else {
        var e2 = emailOf(trimmed)
        if (e2) c.push({ kind: "email", detail: e2, address: e2, actions: [{ id: "mail", model: false, address: e2 }] })
    }
    var tests = [
        function () { return trackingKind(trimmed) },
        function () { return phoneKind(trimmed, true) },
        function () { return errorKind(trimmed) },
        function () { return codeKind(trimmed) },
        function () { return dateKind(trimmed, now, lang) },
        function () { return addressKind(trimmed) },
        function () { return phoneKind(trimmed, false) },
        function () { return amountKind(trimmed, home) },
        function () { return languageKind(trimmed, lang, opts.known) },
        function () { return paragraphKind(trimmed) }
    ]
    // A link or an address alone is that, nothing else.
    if (c.length === 0)
        for (var i = 0; i < tests.length; i++) {
            var k = tests[i]()
            if (!k) continue
            // An error is its own (not also code or a paragraph); code isn't
            // read for dates or addresses.
            var has = c.map(function (x) { return x.kind })
            if ((k.kind === "code" || k.kind === "paragraph" || k.kind === "language") && has.indexOf("error") >= 0) continue
            if ((k.kind === "date" || k.kind === "address" || k.kind === "amount" || k.kind === "paragraph" || k.kind === "language")
                && has.indexOf("code") >= 0) continue
            c.push(k)
        }
    out.candidates = c
    return out
}
