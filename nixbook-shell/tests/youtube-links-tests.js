// YouTube links the shell opens itself (src/modules/common/functions/
// youtube_links.js) under node: what each link is, and what stays with the
// browser. Run by youtube-links.sh.
"use strict";
const fs = require("fs");
const path = require("path");

const src = fs
  .readFileSync(
    path.join(__dirname, "../src/modules/common/functions/youtube_links.js"),
    "utf8",
  )
  .replace(/^\.pragma library/m, "");
const m = new Function(
  src + "\nreturn { linkTarget, wanted, seconds, params }",
)();

let failed = 0,
  passed = 0;
function check(name, actual, expected) {
  const a = JSON.stringify(actual),
    e = JSON.stringify(expected);
  if (a === e) passed++;
  else {
    failed++;
    console.error(`FAIL - ${name}\n       expected ${e}\n       actual   ${a}`);
  }
}
const video = (id, start = 0) => ({ kind: "video", id, list: "", start });
const song = (id, list = "", start = 0) => ({ kind: "song", id, list, start });

const ID = "dQw4w9WgXcQ";
check(
  "watch",
  m.linkTarget(`https://www.youtube.com/watch?v=${ID}`),
  video(ID),
);
check(
  "watch, no www",
  m.linkTarget(`https://youtube.com/watch?v=${ID}`),
  video(ID),
);
check(
  "mobile",
  m.linkTarget(`https://m.youtube.com/watch?v=${ID}&feature=share`),
  video(ID),
);
check("http", m.linkTarget(`http://www.youtube.com/watch?v=${ID}`), video(ID));
check(
  "v not first",
  m.linkTarget(`https://www.youtube.com/watch?list=PLx&v=${ID}&index=3`),
  video(ID),
);
check(
  "t seconds",
  m.linkTarget(`https://www.youtube.com/watch?v=${ID}&t=90s`),
  video(ID, 90),
);
check(
  "t h/m/s",
  m.linkTarget(`https://www.youtube.com/watch?v=${ID}&t=1h2m3s`),
  video(ID, 3723),
);
check(
  "t in the hash",
  m.linkTarget(`https://www.youtube.com/watch?v=${ID}#t=42`),
  video(ID, 42),
);
check(
  "youtu.be",
  m.linkTarget(`https://youtu.be/${ID}?si=abc&t=7`),
  video(ID, 7),
);
check(
  "shorts",
  m.linkTarget(`https://www.youtube.com/shorts/${ID}`),
  video(ID),
);
check(
  "live",
  m.linkTarget(`https://www.youtube.com/live/${ID}?feature=share`),
  video(ID),
);
check(
  "embed",
  m.linkTarget(`https://www.youtube.com/embed/${ID}?start=30`),
  video(ID, 30),
);
check(
  "upper-case host",
  m.linkTarget(`https://WWW.YouTube.com/watch?v=${ID}`),
  video(ID),
);
check("trailing slash", m.linkTarget(`https://youtu.be/${ID}/`), video(ID));

check(
  "song",
  m.linkTarget(`https://music.youtube.com/watch?v=${ID}`),
  song(ID),
);
check(
  "song from a playlist",
  m.linkTarget(`https://music.youtube.com/watch?v=${ID}&list=OLAK5uy_abc`),
  song(ID, "OLAK5uy_abc"),
);
check(
  "song from a radio",
  m.linkTarget(`https://music.youtube.com/watch?v=${ID}&list=RDAMVM${ID}`),
  song(ID, `RDAMVM${ID}`),
);
check(
  "playlist",
  m.linkTarget("https://music.youtube.com/playlist?list=PLabc123"),
  { kind: "playlist", id: "", list: "PLabc123", start: 0 },
);

// Left to the browser.
for (const url of [
  "https://www.youtube.com/",
  "https://www.youtube.com/@channel",
  "https://www.youtube.com/@channel/videos",
  "https://www.youtube.com/results?search_query=cats",
  "https://www.youtube.com/feed/subscriptions",
  "https://www.youtube.com/playlist?list=PLabc",
  "https://www.youtube.com/watch?v=short",
  "https://www.youtube.com/watch",
  "https://music.youtube.com/",
  "https://music.youtube.com/browse/MPREb_x",
  "https://music.youtube.com/channel/UCabc",
  "https://music.youtube.com/watch?list=PLabc",
  "https://youtu.be/",
  "https://notyoutube.com/watch?v=" + ID,
  "https://www.youtube.com.evil.example/watch?v=" + ID,
  "https://youtube.com@evil.example/watch?v=" + ID,
  "https://evil.example/?u=https://www.youtube.com/watch?v=" + ID,
  "javascript:alert(1)//www.youtube.com/watch?v=" + ID,
  "ftp://www.youtube.com/watch?v=" + ID,
  "",
  null,
]) {
  check(`browser: ${url}`, m.linkTarget(url), null);
}

// What the settings take (media.youtubeLinks as the shell writes it).
const v = m.linkTarget(`https://youtu.be/${ID}`);
const s = m.linkTarget(`https://music.youtube.com/watch?v=${ID}`);
const pl = m.linkTarget("https://music.youtube.com/playlist?list=PLabc");
const on = { enable: true, videos: true, music: true };
check("wanted: on, video", m.wanted(v, on), true);
check("wanted: on, song", m.wanted(s, on), true);
check("wanted: on, playlist", m.wanted(pl, on), true);
check(
  "wanted: off",
  m.wanted(v, { enable: false, videos: true, music: true }),
  false,
);
check("wanted: no choice (no shell)", m.wanted(v, null), false);
check(
  "wanted: videos off",
  m.wanted(v, { enable: true, videos: false, music: true }),
  false,
);
check(
  "wanted: videos off, song",
  m.wanted(s, { enable: true, videos: false, music: true }),
  true,
);
check(
  "wanted: music off, playlist",
  m.wanted(pl, { enable: true, videos: true, music: false }),
  false,
);
check("wanted: not a link", m.wanted(null, on), false);

check("seconds plain", m.seconds("75"), 75);
check("seconds m/s", m.seconds("2m5s"), 125);
check("seconds junk", m.seconds("abc"), 0);
check("params decode", m.params("a=b%20c&a=x&d"), { a: "b c", d: "" });

console.log(`${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
