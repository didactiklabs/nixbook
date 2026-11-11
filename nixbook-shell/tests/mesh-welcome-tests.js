// The mesh's welcome back (src/modules/common/functions/mesh_welcome.js)
// under node: which nudges wait for it (sent while away, catching up after
// (re)connecting, locked), how they are grouped (per sender, kind and
// audience, with a count: a long absence is one line, not fifty), and never
// twice. Run by mesh-welcome.sh.
"use strict";
const fs = require("fs");
const path = require("path");

const src = fs
  .readFileSync(
    path.join(__dirname, "../src/modules/common/functions/mesh_welcome.js"),
    "utf8",
  )
  .replace(/^\.pragma library/m, "");
const w = new Function(src + "\nreturn { waits, groups, heldIds, SHOWN }")();

let failed = 0,
  passed = 0;
function check(name, ok, detail) {
  if (ok) passed++;
  else {
    failed++;
    console.error(
      `FAIL - ${name}${detail !== undefined ? `\n       ${JSON.stringify(detail)}` : ""}`,
    );
  }
}

const now = 1_800_000_000_000;
const min = 60 * 1000;
const day = 86400 * 1000;
const live = { now, connectedAt: now - 3600 * 1000, locked: false };
const nudge = (o) =>
  Object.assign(
    {
      mid: "m" + Math.random(),
      from: "anna",
      name: "Anna",
      to: "khoa",
      quick: "pet",
      time: now,
    },
    o,
  );

check(
  "a nudge as it is sent, connected for long, unlocked: its own cut-in",
  !w.waits(nudge(), live),
);
check(
  "sent 11 minutes ago: waits for the welcome",
  w.waits(nudge({ time: now - 11 * min }), live),
);
check(
  "came while locked: waits",
  w.waits(nudge(), Object.assign({}, live, { locked: true })),
);
check(
  "came 2 s after (re)connecting (the catch-up): waits",
  w.waits(
    nudge({ time: now - 30 * 1000 }),
    Object.assign({}, live, { connectedAt: now - 2000 }),
  ),
);
check(
  "over a week old: unread only",
  !w.waits(nudge({ time: now - 8 * day }), live),
);
check(
  "mine: never",
  !w.waits(nudge({ mine: true, time: now - 11 * min }), live),
);
check(
  "a message, not a nudge: never",
  !w.waits(nudge({ quick: undefined, time: now - 11 * min }), live),
);

const nudges = {
  pet: { emoji: "🫳", text: "Head pats" },
  wave: { emoji: "👋", text: "Hi!" },
};
const x = {
  now,
  readAt: { bob: now - 50 * min },
  nudgeOf: (id) => nudges[id] || null,
  conversationOf: (m) => (m.to === "" ? "" : m.from),
  nameOf: (id) => id.toUpperCase(),
};
const held = (o) => nudge(Object.assign({ welcome: true }, o));
// Away all night: Anna patted 50 times, once to everyone, Bob waved twice
// (one already read in the Mesh tab), an old one, one shown already, one
// deleted, one an unknown nudge.
const messages = [];
for (let i = 0; i < 50; i++)
  messages.push(
    held({
      mid: `pat${i}`,
      time: now - (8 * 60 - i) * min,
      name: i === 49 ? "Anna B." : "Anna",
    }),
  );
messages.push(held({ mid: "all", to: "", time: now - 30 * min }));
messages.push(
  held({
    mid: "w1",
    from: "bob",
    name: "",
    quick: "wave",
    time: now - 60 * min,
  }),
);
messages.push(
  held({
    mid: "w2",
    from: "bob",
    name: "",
    quick: "wave",
    time: now - 20 * min,
  }),
);
messages.push(held({ mid: "old", time: now - 8 * day }));
messages.push(held({ mid: "done", greeted: true, time: now - 5 * min }));
messages.push(held({ mid: "gone", deleted: true, time: now - 5 * min }));
messages.push(held({ mid: "odd", quick: "nope", time: now - 5 * min }));
messages.push(nudge({ mid: "plain", time: now - 5 * min }));
const g = w.groups(messages, x);
const lines = g.map(
  (l) =>
    `${l.from}|${l.quick}|${l.to === "" ? "all" : "me"}|${l.count}|${l.name}`,
);
check(
  "grouped per sender, kind and audience, the latest first; read, shown, deleted, unknown and stale ones out",
  JSON.stringify(lines) ===
    JSON.stringify([
      "bob|wave|me|1|BOB",
      "anna|pet|all|1|Anna",
      "anna|pet|me|50|Anna B.",
    ]),
  lines,
);
check(
  "a line says its emoji, words and conversation",
  g[2].emoji === "🫳" &&
    g[2].text === "Head pats" &&
    g[2].conv === "anna" &&
    g[1].conv === "",
  g[2],
);
const ids = w.heldIds(messages);
check(
  "every message held is marked once shown (the read and stale ones too: never shown later)",
  ids.length === 50 + 1 + 2 + 1 + 1 + 1 &&
    !ids.includes("done") &&
    !ids.includes("plain"),
  ids.length,
);
const after = messages.map((m) =>
  ids.includes(m.mid) ? Object.assign({}, m, { greeted: true }) : m,
);
check(
  "shown once: nothing left for a second welcome",
  w.groups(after, x).length === 0 && w.heldIds(after).length === 0,
);
check("four lines on the card", w.SHOWN === 4);

console.log(`${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
