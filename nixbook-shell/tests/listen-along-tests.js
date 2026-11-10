// Listening along's plain code (src/modules/common/functions/track_match.js)
// under node: the same song under another id, a song ending before the
// host's next one comes, a pause, something else played, no endless
// reopening. Run by listen-along.sh.
"use strict";
const fs = require("fs");
const path = require("path");

const src = fs
  .readFileSync(
    path.join(__dirname, "../src/modules/common/functions/track_match.js"),
    "utf8",
  )
  .replace(/^\.pragma library/m, "");
const m = new Function(
  src + "\nreturn { norm, sameSong, fresh, followStep, playStep, seekStep }",
)();

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

// -- The same song ---------------------------------------------------------
const canh = {
  id: "aaaaaaaaaaa",
  title: "Cánh Hoa Héo Tàn",
  artist: "Mr. Siro",
  length: 286,
};
check("the same id", m.sameSong({ id: "aaaaaaaaaaa", title: "x" }, canh));
check(
  "another id, same title and artist (Vietnamese accents)",
  m.sameSong(
    {
      id: "bbbbbbbbbbb",
      title: "Canh Hoa Heo Tan",
      artist: "Mr Siro",
      length: 287,
    },
    canh,
  ),
);
check(
  "the music video's title",
  m.sameSong(
    { id: "c", title: "Cánh Hoa Héo Tàn (Official MV)", artist: "Mr. Siro" },
    canh,
  ),
);
check(
  "feat. dropped",
  m.sameSong(
    {
      id: "c",
      title: "Get Lucky (feat. Pharrell Williams)",
      artist: "Daft Punk",
    },
    { id: "d", title: "Get Lucky", artist: "Daft Punk, Pharrell Williams" },
  ),
);
check(
  "a channel as the artist, same length",
  m.sameSong(
    {
      id: "c",
      title: "Cánh Hoa Héo Tàn",
      artist: "Siro Official Channel",
      length: 288,
    },
    canh,
  ),
);
check(
  "not another song by the same artist",
  !m.sameSong(
    { id: "c", title: "Bước Qua Đời Nhau", artist: "Mr. Siro" },
    canh,
  ),
);
check(
  "not the same title by someone else, another length",
  !m.sameSong(
    { id: "c", title: "Cánh Hoa Héo Tàn", artist: "Someone Else", length: 200 },
    canh,
  ),
);
check(
  "not an empty title",
  !m.sameSong({ id: "c", title: "", artist: "Mr. Siro" }, canh),
);
check("đ folds to d", m.norm("Đời") === "doi", m.norm("Đời"));

// -- Following, tick by tick -------------------------------------------------
function tick(f, now, cur, wantId, want) {
  return m.followStep(f, {
    now,
    wantId: wantId || canh.id,
    want: want || canh,
    cur,
  }).act;
}

// YouTube Music plays the song under another id: synced, never reopened.
{
  const f = m.fresh();
  const acts = [];
  acts.push(tick(f, 0, null));
  for (let t = 1000; t <= 30000; t += 1000)
    acts.push(
      tick(f, t, {
        id: "bbbbbbbbbbb",
        title: "Cánh Hoa Héo Tàn",
        artist: "Mr. Siro",
      }),
    );
  check(
    "another id of the same song: synced",
    acts.slice(1).every((a) => a === "sync"),
    acts,
  );
  check("opened once", acts.filter((a) => a === "open").length === 1, acts);
}
// Something that never takes: three opens at most, 8 s apart.
{
  const f = m.fresh();
  const acts = [];
  for (let t = 0; t <= 60000; t += 1000) acts.push(tick(f, t, null));
  const opens = acts
    .map((a, i) => (a === "open" ? i : -1))
    .filter((i) => i >= 0);
  check("reopened three times at most", opens.length === 3, opens);
  check("8 s apart", opens[1] - opens[0] > 8 && opens[2] - opens[1] > 8, opens);
}
// The song ends here before the host's next one arrives: waits, doesn't leave.
{
  const f = m.fresh();
  tick(f, 0, null);
  tick(f, 1000, canh);
  f.syncedTo = canh.id;
  f.lastLen = 286;
  f.lastPos = 284;
  const next = {
    id: "zzzzzzzzzzz",
    title: "Something Autoplayed",
    artist: "Other",
  };
  const acts = [];
  for (let t = 2000; t <= 9000; t += 1000) acts.push(tick(f, t, next));
  check(
    "autoplay at the end: waits for the host",
    acts.every((a) => a === "wait"),
    acts,
  );
  const song2 = { id: "ccccccccccc", title: "Song Two", artist: "Mr. Siro" };
  check(
    "the host's next song: opened",
    tick(f, 10000, next, song2.id, song2) === "open",
  );
  check("then synced", tick(f, 11000, song2, song2.id, song2) === "sync");
}
// Something else played mid-song: leave, after 3 s (not on loading noise).
{
  const f = m.fresh();
  tick(f, 0, null);
  tick(f, 1000, canh);
  f.syncedTo = canh.id;
  f.lastLen = 286;
  f.lastPos = 100;
  const other = { id: "yyyyyyyyyyy", title: "My Own Pick", artist: "Someone" };
  check("something else: not at once", tick(f, 2000, other) === "wait");
  check("still waiting at 2 s", tick(f, 4000, other) === "wait");
  check("left after 3 s", tick(f, 5000, other) === "leave");
}
// Passing metadata while it loads: back on the song, nothing happens.
{
  const f = m.fresh();
  tick(f, 0, null);
  tick(f, 1000, canh);
  f.syncedTo = canh.id;
  f.lastLen = 286;
  f.lastPos = 100;
  tick(f, 2000, { id: "yyyyyyyyyyy", title: "Loading…" });
  check("a blip: synced again", tick(f, 3000, canh) === "sync");
  check(
    "and the clock reset",
    tick(f, 4000, { id: "yyyyyyyyyyy", title: "x" }) === "wait" &&
      tick(f, 6500, { id: "yyyyyyyyyyy", title: "x" }) === "wait",
  );
}
// The host switches mid-song: the new one opened, never a leave.
{
  const f = m.fresh();
  tick(f, 0, null);
  tick(f, 1000, canh);
  f.syncedTo = canh.id;
  f.lastLen = 286;
  f.lastPos = 50;
  const song2 = { id: "ccccccccccc", title: "Song Two", artist: "Mr. Siro" };
  check(
    "the host switched: opened",
    tick(f, 2000, canh, song2.id, song2) === "open",
  );
  check("loading: waits", tick(f, 3000, canh, song2.id, song2) === "wait");
  check("on it: synced", tick(f, 4000, song2, song2.id, song2) === "sync");
}

// -- Play and pause ------------------------------------------------------------
function play(f, now, local, recv) {
  return m.playStep(f, {
    now,
    hostPlaying: true,
    localPlaying: local,
    hostRecv: recv || 0,
  });
}
{
  const f = m.fresh();
  f.openedAt = 0;
  f.lastLen = 286;
  f.lastPos = 100;
  check("not playing yet after an open: play", play(f, 2500, false) === "play");
  check("playing", play(f, 4000, true) === "ok");
  const acts = [];
  for (let t = 20000; t <= 24000; t += 1000) acts.push(play(f, t, false));
  check(
    "paused: not at once",
    acts.every((a) => a === "ok"),
    acts,
  );
  check("paused 5 s: leave", play(f, 25000, false) === "leave");
}
{
  const f = m.fresh();
  f.lastLen = 286;
  f.lastPos = 280;
  play(f, 9000, true);
  const acts = [];
  for (let t = 20000; t <= 40000; t += 1000) acts.push(play(f, t, false));
  check(
    "stopped at the song's end: never a leave",
    !acts.includes("leave"),
    acts,
  );
}
{
  const f = m.fresh();
  f.lastLen = 286;
  f.lastPos = 100;
  play(f, 9000, true);
  const acts = [];
  for (let t = 20000; t <= 30000; t += 1000)
    acts.push(play(f, t, false, t - 1000));
  check("the host just sent news: no leave", !acts.includes("leave"), acts);
}
{
  const f = m.fresh();
  check(
    "the host paused: pause here",
    m.playStep(f, {
      now: 5000,
      hostPlaying: false,
      localPlaying: true,
      hostRecv: 0,
    }) === "pause",
  );
}

// -- Jumping to the host's position ---------------------------------------------
function seek(f, now, pos, target, recv) {
  return m.seekStep(f, { now, pos, target, len: 286, hostRecv: recv || 1 });
}
{
  const f = m.fresh();
  f.openedFor = canh.id;
  f.openedAt = 0;
  check("not while it loads", seek(f, 1000, 0, 40) === -1);
  check("once it opened, to the host", seek(f, 3000, 1, 42) === 42);
  // Its position reported badly (stuck), the host silent: no jump every 4 s.
  const jumps = [];
  for (let t = 4000; t <= 32000; t += 1000)
    if (seek(f, t, 1, 42 + (t - 3000) / 1000) >= 0) jumps.push(t);
  check("a drift: no jump every few seconds", jumps.length === 0, jumps);
  check("a drift: at most every 30 s", seek(f, 34000, 1, 73) === 73);
  check("the host seeks: followed", seek(f, 40000, 80, 150, 2) === 150);
  check(
    "the host's news, no drift: nothing",
    seek(f, 50000, 160, 160, 3) === -1,
  );
  check("not at the song's end", seek(f, 90000, 100, 285, 4) === -1);
}
{
  const f = m.fresh();
  f.openedFor = canh.id;
  check(
    "opened at the right spot: no jump",
    m.seekStep(f, { now: 5000, pos: 41, target: 42, len: 286, hostRecv: 1 }) ===
      -1,
  );
}

console.log(`${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
