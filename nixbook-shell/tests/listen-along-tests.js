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
  src +
    "\nreturn { norm, sameSong, fresh, followStep, playStep, seekStep, goneStep }",
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
// Something that never takes: two opens at most, 12 s apart.
{
  const f = m.fresh();
  const acts = [];
  for (let t = 0; t <= 60000; t += 1000) acts.push(tick(f, t, null));
  const opens = acts
    .map((a, i) => (a === "open" ? i : -1))
    .filter((i) => i >= 0);
  check("opened twice at most: no retry loop", opens.length === 2, opens);
  check("12 s apart", opens[1] - opens[0] > 12, opens);
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
  for (let t = 20000; t <= 27000; t += 1000) acts.push(play(f, t, false));
  check(
    "paused: not at once",
    acts.every((a) => a === "ok"),
    acts,
  );
  check(
    "paused 8 s: held, not left (a media key, a click by mistake)",
    play(f, 28000, false) === "hold",
  );
  check(
    "held: nothing played for them, the host playing on",
    play(f, 60000, false) === "hold" && play(f, 600000, false) === "hold",
  );
  check(
    "play pressed again: resume, caught up",
    play(f, 601000, true) === "resume" && !f.held,
  );
  check("then playing along again", play(f, 602000, true) === "ok");
  const acts2 = [];
  for (let t = 700000; t <= 707000; t += 1000) acts2.push(play(f, t, false));
  check(
    "paused again: held again after 8 s",
    acts2.every((a) => a === "ok") && play(f, 708000, false) === "hold",
  );
  check(
    "held 30 minutes: they've moved on, leave",
    play(f, 708000 + 30 * 60 * 1000, false) === "leave",
  );
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
  return m.seekStep(f, {
    now,
    pos,
    target,
    len: 286,
    hostRecv: recv || 1,
    playing: true,
  });
}
{
  const f = m.fresh();
  f.openedFor = canh.id;
  f.openedAt = 0;
  check("not while it loads", seek(f, 1000, 0, 40) === -1);
  check(
    "not while YouTube Music shows 0 on its way to &t= (3 s)",
    seek(f, 3000, 0, 42) === -1,
  );
  check("once it opened, to the host", seek(f, 6500, 1, 45) === 45);
  // Its position reported badly (stuck), the host silent: no jump every 4 s.
  const jumps = [];
  for (let t = 7000; t <= 36000; t += 1000)
    if (seek(f, t, 1, 45 + (t - 6500) / 1000) >= 0) jumps.push(t);
  check("a drift: no jump every few seconds", jumps.length === 0, jumps);
  check("a drift: at most every 30 s", seek(f, 37000, 1, 76) === 76);
  check("the host seeks: followed", seek(f, 42000, 80, 150, 2) === 150);
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
    "opened at the right spot (&t=): no jump",
    m.seekStep(f, { now: 7000, pos: 41, target: 42, len: 286, hostRecv: 1 }) ===
      -1,
  );
}

// -- Slack: a slow start, a small drift, a stuck position ---------------------
function seekAt(f, now, pos, target, opts) {
  return m.seekStep(
    f,
    Object.assign(
      { now, pos, target, len: 286, hostRecv: 1, playing: true },
      opts || {},
    ),
  );
}
{
  const f = m.fresh();
  f.openedFor = "x";
  const jumps = [];
  // Spotify right after it starts: "Playing", its position stuck at 0.
  for (let t = 1000; t <= 20000; t += 1000)
    if (seekAt(f, t, 0, 40 + t / 1000) >= 0) jumps.push(t);
  check("a position not moving: no jump", jumps.length === 0, jumps);
  check("then it moves: the first jump", seekAt(f, 21000, 0.5, 61) === 61);
}
{
  const f = m.fresh();
  f.openedFor = "x";
  seekAt(f, 6000, 10, 10);
  seekAt(f, 7000, 11, 11);
  const jumps = [];
  for (let t = 8000; t <= 80000; t += 1000)
    if (seekAt(f, t, (t - 4000) / 1000, t / 1000) >= 0) jumps.push(t);
  check("a 4 s drift: left alone", jumps.length === 0, jumps);
}
{
  const f = m.fresh();
  f.openedFor = "x";
  seekAt(f, 6000, 10, 10);
  seekAt(f, 7000, 11, 11);
  check("a 6 s drift: not before 30 s", seekAt(f, 20000, 18, 24) === -1);
  check("a 6 s drift: corrected", seekAt(f, 40000, 38, 44) === 44);
  check(
    "the host's news, 3 s apart: followed",
    seekAt(f, 50000, 47, 50, { hostRecv: 2 }) === 50,
  );
  check(
    "not paused here (a jump only while playing… the first)",
    seekAt(f, 60000, 57, 57, { hostRecv: 3, playing: false }) === -1,
  );
}
{
  const f = m.fresh();
  tick(f, 0, null);
  check("a slow load: not reopened at 9 s", tick(f, 9000, null) === "wait");
  check("reopened after 12 s", tick(f, 12500, null) === "open");
}

// -- A version not playable here: another one opened instead -----------------
{
  const f = m.fresh();
  const want = {
    id: "7wZ_bFmEN5Q",
    title: "Người Lạ Ơi (Solo Version)",
    artist: "Orange & Superbrothers",
    length: 224,
  };
  const other = {
    id: "zzzzzzzzzzz",
    title: "Something Next In The Queue",
    artist: "Someone",
  };
  const step = (now, cur) =>
    m.followStep(f, { now, wantId: want.id, want, cur }).act;
  check("opened", step(0, null) === "open");
  check(
    "YouTube Music went on with its queue: the second try at once",
    step(5000, other) === "open" && f.opens === 2,
  );
  f.alt = "aaaaaaaaaaa";
  f.altFor = want.id;
  check(
    "the other version, whatever its title: synced",
    step(14000, {
      id: "aaaaaaaaaaa",
      title: "NGUOI LA OI",
      artist: "Orange",
    }) === "sync",
  );
  check(
    "a new song from the host: tried versions forgotten",
    m.followStep(f, {
      now: 20000,
      wantId: "bbbbbbbbbbb",
      want: { id: "bbbbbbbbbbb", title: "Next" },
      cur: null,
    }).act === "open" &&
      f.alt === "" &&
      f.tried.length === 0,
  );
}

// -- The open lands on another song: the second try at once -------------------
{
  const f = m.fresh();
  const want = {
    id: "7wZ_bFmEN5Q",
    title: "Người Lạ Ơi (Solo Version)",
    artist: "Orange & Superbrothers",
  };
  const was = { id: "MDS9Cp5kmxQ", title: "Vì Yêu Cứ Đâm Đầu", artist: "MIN" };
  const queue = {
    id: "qqqqqqqqqqq",
    title: "Next In Her Queue",
    artist: "Someone",
  };
  const step = (now, cur) =>
    m.followStep(f, { now, wantId: want.id, want, cur }).act;
  check("opened", step(0, was) === "open");
  check(
    "still loading (the song it played): waits",
    step(1000, was) === "wait" && step(2500, was) === "wait",
  );
  check(
    "moved to another song: the second try at once",
    step(3500, queue) === "open" && f.opens === 2,
  );
  check(
    "then no more",
    step(5000, queue) === "wait" && step(30000, queue) === "wait",
  );
}

// -- The player gone ----------------------------------------------------------
// The background player leaves the bus when its one-song queue ends: not
// "you closed it" (that kicked listeners out between songs).
{
  const synced = () =>
    Object.assign(m.fresh(), {
      syncedTo: "song1111111",
      lastPos: 178,
      lastLen: 180,
    });
  let f = synced();
  const gone = (now, wantId, extra) =>
    m.goneStep(
      f,
      Object.assign({ now, wantId, background: true, target: 180 }, extra),
    );
  check(
    "background, gone at its song's end: waits for the host's next song, however long",
    gone(0, "song1111111") === "next" && gone(60000, "song1111111") === "next",
  );
  check(
    "…the host's next song: opened",
    gone(61000, "song2222222") === "reopen",
  );
  f = synced();
  check(
    "…the host started it again (repeat one): opened",
    gone(0, "song1111111", { target: 3 }) === "reopen",
  );
  f = Object.assign(synced(), { lastPos: 60 });
  check(
    "background, gone in the middle of the song (stopped): out after 5 s",
    gone(1000, "song1111111") === "wait" &&
      gone(5000, "song1111111") === "wait" &&
      gone(6000, "song1111111") === "leave",
  );
  f = synced();
  check(
    "an app gone (closed), even at the song's end: out after 5 s",
    m.goneStep(f, { now: 1000, wantId: "song1111111", background: false }) ===
      "wait" &&
      m.goneStep(f, { now: 6000, wantId: "song1111111", background: false }) ===
        "leave",
  );
}

console.log(`${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
