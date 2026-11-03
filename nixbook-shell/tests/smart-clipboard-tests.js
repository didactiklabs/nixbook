// The smart clipboard's classifier (src/modules/common/functions/
// clipboard_kinds.js) on real-world samples: each kind in the four
// languages, the negatives, and the secrets never offered. Run by
// smart-clipboard.sh (node, TZ=Europe/Paris).
"use strict";
const fs = require("fs");
const path = require("path");

const src = fs
  .readFileSync(
    path.join(__dirname, "../src/modules/common/functions/clipboard_kinds.js"),
    "utf8",
  )
  .replace(/^\.pragma library/m, "");
const lib = new Function(
  src +
    "\nreturn { classify: classify, languageOf: languageOf, upsValid: upsValid, s10Valid: s10Valid }",
)();

// Thursday 29 October 2026, 10:00.
const NOW = new Date(2026, 9, 29, 10, 0, 0);
let failed = 0,
  passed = 0;
function check(name, ok, detail) {
  if (ok) {
    passed++;
    return;
  }
  failed++;
  console.log(`FAIL ${name}${detail ? " — " + detail : ""}`);
}
function top(text, opts) {
  const r = lib.classify(
    text,
    Object.assign({ now: NOW, lang: "en" }, opts || {}),
  );
  return r;
}
function kindOf(text, opts) {
  const r = top(text, opts);
  return r.secret ? "secret" : r.candidates.length ? r.candidates[0].kind : "";
}
function expectKind(kind, samples, opts) {
  for (const s of samples) {
    const got = kindOf(s, opts);
    check(
      `${kind}: ${JSON.stringify(s).slice(0, 70)}`,
      got === kind,
      `got ${got || "nothing"}`,
    );
  }
}
function expectNot(kind, samples, opts) {
  for (const s of samples) {
    const r = top(s, opts);
    const kinds = r.candidates.map((c) => c.kind);
    check(
      `not ${kind}: ${JSON.stringify(s).slice(0, 70)}`,
      !kinds.includes(kind),
      `got ${kinds.join(",")}`,
    );
  }
}
function ymdhm(ms) {
  const d = new Date(ms);
  const p = (n) => (n < 10 ? "0" : "") + n;
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
}

// ── Check digits ──
check("UPS sample check digit", lib.upsValid("1Z999AA10123456784"));
check("UPS wrong check digit", !lib.upsValid("1Z999AA10123456785"));
check("S10 check digit", lib.s10Valid("RR123456785FR"));
check("S10 wrong check digit", !lib.s10Valid("RR123456789FR"));

// ── Secrets: never offered ──
const secrets = [
  "Tr0ub4dor&3",
  "hunter2Hunter2",
  "P@ssw0rd!",
  "aB3dE6gH9jK2",
  "123456",
  "482 913",
  "84721093",
  "Your verification code is 482913",
  "Votre code de vérification : 552301",
  "Ihr Bestätigungscode lautet 991204",
  "Mã xác nhận của bạn là 448812",
  "Use 7731 as your login code",
  "sk-proj-abcdefghijklmnopqrstuvwxyz012345",
  "ghp_abcdefghijklmnopqrstuvwxyz0123456789",
  "AKIAIOSFODNN7EXAMPLE",
  "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U",
  "-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAA\n-----END OPENSSH PRIVATE KEY-----",
  "password=SuperSecret",
  "DB_PASSWORD: hunter2",
  "export API_KEY=abc123def",
  "mot de passe : soleil42",
  "https://user:s3cret@example.com/repo.git",
  "Authorization: Bearer abcdefghijklmnop1234",
  "4111 1111 1111 1111",
  "4111111111111111",
  "FR76 3000 6000 0112 3456 7890 189",
  "d41d8cd98f00b204e9800998ecf8427e",
  "dGhpcyBpcyBhIGJhc2U2NCB0b2tlbjEyMw==",
];
for (const s of secrets)
  check(
    `secret: ${JSON.stringify(s).slice(0, 60)}`,
    top(s).secret,
    `got ${kindOf(s)}`,
  );
// Copied while a password manager is in front: never, whatever it is.
check(
  "password manager app",
  top("https://example.com", { app: "org.keepassxc.KeePassXC" }).secret,
);
check(
  "bitwarden app",
  top("12 rue de Rivoli, 75001 Paris", { app: "Bitwarden" }).secret,
);
// Not secrets.
for (const s of [
  "1Z999AA10123456784",
  "RR123456785FR",
  "+33 6 12 34 56 78",
  "jean.dupont@example.fr",
  "https://www.example.com/a?b=1",
])
  check(`not secret: ${s}`, !top(s).secret, top(s).why);

// ── Tracking numbers ──
expectKind("tracking", [
  "1Z999AA10123456784",
  "Your UPS package 1Z999AA10123456784 is on its way",
  "RR123456785FR",
  "Votre colis RR123456785FR a été expédié",
  "Sendung RR123456785DE ist unterwegs",
  "6A12345678901",
  "Numéro de suivi Colissimo : 6A12345678901",
  "8R00123456789",
  "JJD000390007551234567",
  "00340434161234567890",
  "FedEx tracking number: 123456789012",
  "DHL Express 1234567890",
  "Ihre DHL Sendungsnummer: 00340434161234567890",
  "Mã vận đơn: RR123456785VN",
  "Tracking: LX123456785CN",
]);
{
  const t = top("Votre colis RR123456785FR a été expédié").candidates[0];
  check(
    "La Poste link",
    t.actions[0].url.indexOf("laposte.fr") > 0 && t.detail === "La Poste",
    JSON.stringify(t),
  );
  const u = top("1Z999AA10123456784").candidates[0];
  check(
    "UPS link",
    /ups\.com\/track\?tracknum=1Z999AA10123456784/.test(u.actions[0].url),
  );
  const c = top("Chronopost EE123456785FR").candidates[0];
  check(
    "Chronopost",
    c.detail === "Chronopost" && c.actions[0].url.indexOf("chronopost.fr") > 0,
    JSON.stringify(c),
  );
  const f = top("FedEx tracking number: 123456789012").candidates[0];
  check(
    "FedEx",
    f.detail === "FedEx" && f.actions[0].url.indexOf("trknbr=123456789012") > 0,
    JSON.stringify(f),
  );
  const o = top("Tracking: LX123456785CN").candidates[0];
  check("other carrier: 17track", o.actions[0].url.indexOf("17track") > 0);
}
expectNot("tracking", [
  "123456789012",
  "Order #A1234 confirmed",
  "RR123456789FR",
  "1Z999AA10123456785",
  "ISBN 9780306406157",
]);

// ── Phone numbers ──
expectKind("phone", [
  "+33 6 12 34 56 78",
  "06 12 34 56 78",
  "0612345678",
  "+49 30 1234567",
  "030 1234567",
  "(555) 123-4567",
  "+1 555-123-4567",
  "+84 912 345 678",
  "0912 345 678",
  "tel:+33612345678",
  "Tél. : 01 23 45 67 89",
]);
{
  const p = top("06 12 34 56 78").candidates[0];
  check(
    "phone number normalized",
    p.number === "0612345678" &&
      p.actions[0].id === "call" &&
      p.actions[1].id === "text",
    JSON.stringify(p),
  );
  const q = top("Appelle-moi au 06 12 34 56 78 stp").candidates.map(
    (c) => c.kind,
  );
  check("phone inside a short text", q.indexOf("phone") >= 0, q.join(","));
}
expectNot("phone", [
  "2026-10-29",
  "12/11/2026",
  "3.14159",
  "1.2.3",
  "v2.10.4",
  "15:30",
  "Page 12 of 40",
]);

// ── Links and e-mail ──
expectKind("url", [
  "https://www.lemonde.fr/economie/article/2026/10/29/x.html",
  "www.spiegel.de/politik",
  "https://vnexpress.net/abc-123.html",
  "https://news.ycombinator.com/item?id=4242)",
]);
{
  const u = top("https://www.lemonde.fr/economie/article.html").candidates[0];
  check(
    "url actions",
    u.actions[0].id === "summarizePage" &&
      u.actions[1].id === "open" &&
      u.detail === "lemonde.fr",
    JSON.stringify(u),
  );
  const local = top("http://192.168.1.10:8080/admin").candidates[0];
  check(
    "private link: open only",
    local.actions.length === 1 && local.actions[0].id === "open",
    JSON.stringify(local),
  );
  const keyed = top("https://example.com/reset?token=abc").candidates;
  check(
    "link with a key: open only (or secret)",
    keyed.length === 0 || keyed[0].actions.every((a) => !a.model),
    JSON.stringify(keyed),
  );
}
expectKind("email", [
  "jean.dupont@example.fr",
  "mailto:anna.schmidt@example.de",
  "Nguyễn Văn An <an.nguyen@example.vn>",
]);
check(
  "email action",
  top("jean.dupont@example.fr").candidates[0].actions[0].id === "mail",
);

// ── Errors ──
expectKind("error", [
  "Traceback (most recent call last):\n  File \"main.py\", line 3, in <module>\n    import foo\nModuleNotFoundError: No module named 'foo'",
  "error[E0382]: borrow of moved value: `x`\n --> src/main.rs:4:20",
  "TypeError: Cannot read properties of undefined (reading 'map')\n    at App (App.js:12:15)\n    at renderWithHooks (react-dom.js:1:2)",
  "npm ERR! code ERESOLVE\nnpm ERR! ERESOLVE unable to resolve dependency tree",
  "bash: nixos-rebuil: command not found",
  "error: attribute 'foo' missing\n       at /etc/nixos/configuration.nix:12:3",
  'Exception in thread "main" java.lang.NullPointerException\n\tat com.example.Main.main(Main.java:5)',
  "Segmentation fault (core dumped)",
  "Erreur : fichier introuvable",
  "Fehler: Datei nicht gefunden",
  "panic: runtime error: index out of range [3] with length 3\n\ngoroutine 1 [running]:",
]);
{
  const e = top("bash: nixos-rebuil: command not found").candidates[0];
  check(
    "error actions",
    e.actions[0].id === "explain" && e.actions[1].id === "fixError",
    JSON.stringify(e),
  );
}
expectNot("error", [
  "The meeting failed to start on time, so we moved it.",
  "Merci pour votre aide !",
]);

// ── Code ──
expectKind("code", [
  "def add(a, b):\n    return a + b",
  "const xs = items.map(x => x * 2);\nconsole.log(xs);",
  "{ pkgs, ... }:\n{\n  environment.systemPackages = [ pkgs.git ];\n}",
  "SELECT name, count(*) FROM users\nWHERE active = 1\nGROUP BY name;",
  "git rebase -i HEAD~3",
  "sudo systemctl restart nixbook-shell --user",
  "kubectl get pods -n kube-system | grep coredns",
  '<div class="card">\n  <span>{{ title }}</span>\n</div>',
  'fn main() {\n    println!("hello");\n}',
]);
expectNot("code", [
  "Hello, how are you?",
  "Rendez-vous demain à 14h",
  "Ich komme morgen um 15 Uhr.",
]);

// ── Dates and times ──
function expectDate(text, want, opts) {
  const r = top(text, opts);
  const d = r.candidates.find((c) => c.kind === "date");
  check(
    `date: ${JSON.stringify(text).slice(0, 60)}`,
    d && ymdhm(d.when) === want && r.candidates[0].kind === "date",
    d
      ? `got ${ymdhm(d.when)} (${r.candidates[0].kind})`
      : `no date (${r.candidates.map((c) => c.kind).join(",")})`,
  );
  return d;
}
expectDate("next Tuesday 3pm", "2026-11-03 15:00");
expectDate("Lunch with Sam tomorrow at 12:30", "2026-10-30 12:30");
expectDate("Meeting on November 12 at 2:30 pm", "2026-11-12 14:30");
expectDate("Dentist appointment Friday at 9am", "2026-10-30 09:00");
expectDate("Call at noon on Monday", "2026-11-02 12:00");
expectDate("12/11/2026 15:00 project review", "2026-12-11 15:00", {
  lang: "en",
});
expectDate("2026-12-24 18:00 Christmas dinner", "2026-12-24 18:00");
expectDate("Thursday 5pm drinks", "2026-10-29 17:00");
expectDate("Party on Thursday 9am", "2026-11-05 09:00");
expectDate("le 12 novembre à 14h", "2026-11-12 14:00", { lang: "fr" });
expectDate("Réunion mardi prochain à 10h30", "2026-11-03 10:30", {
  lang: "fr",
});
expectDate("RDV demain 9h chez le médecin", "2026-10-30 09:00", { lang: "fr" });
expectDate("Dîner samedi à 20h", "2026-10-31 20:00", { lang: "fr" });
expectDate("Rendez-vous le 03/11 à 15h30", "2026-11-03 15:30", { lang: "fr" });
expectDate("après-demain à midi", "2026-10-31 12:00", { lang: "fr" });
expectDate("Termin am 12. November um 15 Uhr", "2026-11-12 15:00", {
  lang: "de",
});
expectDate("Treffen nächsten Dienstag um 14:30", "2026-11-03 14:30", {
  lang: "de",
});
expectDate("morgen um 9 Uhr Zahnarzt", "2026-10-30 09:00", { lang: "de" });
expectDate("Abgabe 15.12.2026", "2026-12-15 00:00", { lang: "de" });
expectDate("übermorgen 18 Uhr Kino", "2026-10-31 18:00", { lang: "de" });
expectDate("Họp lúc 3 giờ chiều ngày mai", "2026-10-30 15:00", { lang: "vi" });
expectDate("ngày 12 tháng 11 lúc 9 giờ sáng", "2026-11-12 09:00", {
  lang: "vi",
});
expectDate("Thứ hai tuần sau 10 giờ", "2026-11-02 10:00", { lang: "vi" });
expectDate("Friday next week 3pm", "2026-11-06 15:00");
expectDate("Thứ sáu tuần sau lúc 9 giờ sáng", "2026-11-06 09:00", {
  lang: "vi",
});
expectDate("Hẹn gặp chủ nhật lúc 15:00", "2026-11-01 15:00", { lang: "vi" });
expectDate("January 5th dinner with Anna", "2027-01-05 00:00");
// Said in another time zone: put in the local time (TZ=Europe/Paris, CET
// since 25 October; the US on daylight time until 1 November).
{
  const d = expectDate("Nov 4th at 9:00 PM ET.", "2026-11-05 03:00");
  check("zone said", d && d.said === "9:00 PM ET", d && JSON.stringify(d.said));
}
expectDate("Meeting October 30 at 9am ET", "2026-10-30 14:00");
expectDate("Launch call Nov 2 at 10am PT", "2026-11-02 19:00");
expectDate("Call tomorrow 3pm Eastern Time", "2026-10-30 20:00");
expectDate("Webinar le 12 novembre à 15h UTC", "2026-11-12 16:00", {
  lang: "fr",
});
expectDate("Standup Monday 10:00 UTC+7", "2026-11-02 04:00");
expectDate("Demo on July 1 at 9am CET", "2027-07-01 09:00");
expectDate("Sync Friday 4pm (PST)", "2026-10-31 01:00");
{
  const d = expectDate("RDV demain à 14h et on verra", "2026-10-30 14:00", {
    lang: "fr",
  });
  check("no zone in French 'et'", d && !d.said, d && JSON.stringify(d.said));
}
{
  const d = expectDate("Lunch with Sam tomorrow at 12:30", "2026-10-30 12:30");
  check(
    "date title",
    d && d.title === "Lunch with Sam",
    d && JSON.stringify(d.title),
  );
  const f = expectDate("Réunion mardi prochain à 10h30", "2026-11-03 10:30", {
    lang: "fr",
  });
  check(
    "date title fr",
    f && f.title === "Réunion",
    f && JSON.stringify(f.title),
  );
  const loc = top("Dinner Friday 8pm at 12 rue de Rivoli, 75001 Paris")
    .candidates[0];
  check(
    "date with a place",
    loc.kind === "date" && /Rivoli.*Paris/.test(loc.location),
    JSON.stringify(loc),
  );
  const n = top("Abgabe 15.12.2026", { lang: "de" }).candidates[0];
  check("a day without a time", n.hasTime === false);
}
expectNot("date", [
  "3/4 cup of sugar",
  "Version 1.5 released",
  "at 3pm",
  "You may 5 times try",
  "Guten Morgen, wie geht's?",
  "Pi is 3.14",
  "Room 12.11",
  "I march 5 miles every day",
]);

// ── Addresses ──
expectKind("address", [
  "12 rue de Rivoli, 75001 Paris",
  "8 avenue des Champs-Élysées\n75008 Paris",
  "Hauptstraße 5, 10115 Berlin",
  "Musterweg 12a\n80331 München",
  "1600 Amphitheatre Parkway, Mountain View, CA 94043",
  "221B Baker Street, London NW1 6XE",
  "12 đường Lê Lợi, phường Bến Nghé, quận 1, TP. Hồ Chí Minh",
  "Số 5 phố Hàng Bài, quận Hoàn Kiếm, Hà Nội",
]);
{
  const a = top("12 rue de Rivoli, 75001 Paris").candidates[0];
  check(
    "address actions",
    a.actions[0].id === "directions" &&
      a.actions[0].url.indexOf("destination=12%20rue%20de%20Rivoli") > 0,
    JSON.stringify(a),
  );
}
expectNot("address", [
  "I have 3 place settings",
  "2 cours de maths demain",
  "String 5",
  "I walked 3 miles down the road",
  "Bring 3 apples",
]);

// ── Amounts ──
expectKind(
  "amount",
  [
    "€25",
    "25 €",
    "1.299,99 €",
    "$1,299.99",
    "49,99 EUR",
    "500.000 ₫",
    "100 USD",
    "£12.50",
    "CHF 80",
    "2 500 000 đồng",
  ],
  { lang: "fr" },
);
{
  const a = top("$1,299.99", { lang: "fr" }).candidates[0];
  check(
    "amount value",
    a.amount === 1299.99 && a.currency === "USD" && a.actions[0].to === "EUR",
    JSON.stringify(a),
  );
  const b = top("1.299,99 €", { lang: "fr" }).candidates[0];
  check(
    "amount in euros (fr user)",
    b.amount === 1299.99 && b.actions[0].to === "USD",
    JSON.stringify(b),
  );
  const v = top("500.000 ₫", { lang: "fr" }).candidates[0];
  check("dong", v.amount === 500000 && v.currency === "VND", JSON.stringify(v));
  const e = top("25 €", { lang: "vi" }).candidates[0];
  check("to the vi user's dong", e.actions[0].to === "VND");
}
expectNot("amount", ["12 rue de Rivoli", "25 people", "Version 2"]);

// ── Languages ──
const fr =
  "Bonjour, je voulais savoir si vous étiez disponible pour une réunion la semaine prochaine avec toute l'équipe.";
const de =
  "Hallo, ich wollte fragen, ob du nächste Woche Zeit für ein kurzes Treffen mit dem ganzen Team hast.";
const vi =
  "Xin chào, tôi muốn hỏi bạn có rảnh để họp với cả nhóm vào tuần sau không.";
const en =
  "Hi, I wanted to ask whether you are available for a short meeting with the whole team next week.";
const es =
  "Hola, quería saber si estás disponible para una reunión con todo el equipo la semana que viene.";
const ja = "来週、チーム全員で短い打ち合わせをする時間はありますか？";
const ru =
  "Привет, хотел спросить, будешь ли ты свободен на следующей неделе для короткой встречи.";
check("fr detected", lib.languageOf(fr) === "fr", lib.languageOf(fr));
check("de detected", lib.languageOf(de) === "de", lib.languageOf(de));
check("vi detected", lib.languageOf(vi) === "vi", lib.languageOf(vi));
check("en detected", lib.languageOf(en) === "en", lib.languageOf(en));
check("es detected", lib.languageOf(es) === "es", lib.languageOf(es));
check("ja detected", lib.languageOf(ja) === "ja", lib.languageOf(ja));
check("ru detected", lib.languageOf(ru) === "ru", lib.languageOf(ru));
expectKind("language", [de, vi, en, es, ja, ru], { lang: "fr" });
expectKind("language", [fr, de, vi, es], { lang: "en" });
expectNot("language", [fr], { lang: "fr" });
expectNot("language", [en], { lang: "fr", known: ["en"] });
expectNot("language", ["OK merci", "Hello there"], { lang: "fr" });
{
  const t = top(de, { lang: "fr" }).candidates[0];
  check(
    "translate into the user's language",
    t.actions[0].id === "translate" &&
      t.actions[0].to === "fr" &&
      t.actions[0].from === "de",
  );
}

// ── A long paragraph ──
const para =
  "The committee met on several occasions over the summer to review the proposals that had been submitted. " +
  "Each proposal was assessed against the criteria published in the spring, with particular attention paid to cost, " +
  "feasibility and the expected benefit for residents. After long discussions, three projects were shortlisted for " +
  "a public consultation that will take place in the coming months. The final decision is expected before the end of " +
  "the year, once the results of the consultation have been analysed and presented to the council.";
expectKind("paragraph", [para]);
{
  const p = top(para).candidates[0];
  check(
    "paragraph actions",
    p.actions[0].id === "summarize" && p.actions[1].id === "rewrite",
  );
  const f = top(para, { lang: "fr" }).candidates.map((c) => c.kind);
  check(
    "a long English paragraph for a French user: translate first",
    f[0] === "language" && f.indexOf("paragraph") > 0,
    f.join(","),
  );
}

// ── Nothing ──
for (const s of [
  "",
  "ok",
  "Thanks!",
  "lol",
  "42",
  "Hello there",
  "Sounds good to me",
])
  check(
    `nothing: ${JSON.stringify(s)}`,
    top(s).candidates.length === 0 && !top(s).secret,
    kindOf(s),
  );

// ── Speed: a few milliseconds each ──
{
  const samples = [
    para,
    fr,
    "le 12 novembre à 14h",
    "1Z999AA10123456784",
    "12 rue de Rivoli, 75001 Paris",
    'Traceback (most recent call last):\n  File "x", line 1\nValueError: x',
    "x".repeat(19000),
  ];
  const t0 = Date.now();
  for (let i = 0; i < 50; i++)
    for (const s of samples) lib.classify(s, { now: NOW, lang: "fr" });
  const per = (Date.now() - t0) / (50 * samples.length);
  check(`fast (${per.toFixed(2)} ms per text)`, per < 5);
  console.log(`${per.toFixed(2)} ms per text`);
}

console.log(`${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
