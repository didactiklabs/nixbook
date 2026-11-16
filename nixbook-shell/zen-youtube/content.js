// nixbook-shell's YouTube links, inside YouTube's own pages.
//
// A plain click on a link there changes the page in place (no page load the
// background page could stop), so it is taken here first and handed to the
// shell (background.js), when the shell wants that kind of link (the choice
// the background page keeps in storage.local). When the shell can't take it
// the link opens in the page as a normal link would. Ctrl/Shift/middle
// clicks open a tab or a window: a page load, which background.js sees.
//
// Videos with media.youtubeLinks.onPlay (on by default): their page stays in
// the browser (the description, the comments), and the video goes to mpv
// only when play is pressed on its player: a play of the page's video within
// PRESS_MS of a press on the player (a click or a tap on it or its play
// button, k, Space, the play/pause media key) is stopped and handed to the
// shell with the time it is at; a play nobody pressed (YouTube's autoplay)
// is only stopped, so the page doesn't play on its own while it is read.
// When the shell can't take the video it plays here, and that video keeps
// playing here until another one is opened. Shorts aren't taken: they play
// in the page.
"use strict";

const PRESS_MS = 1500;
const AGAIN_MS = 3000;
const PLAYERS = "#movie_player, #player-container-id";

let choice = null;
browser.storage.local.get("choice").then(
  (r) => {
    choice = r.choice || null;
  },
  () => {},
);
browser.storage.onChanged.addListener((changes, area) => {
  if (area === "local" && changes.choice)
    choice = changes.choice.newValue || null;
});

function linkIn(e) {
  const path = typeof e.composedPath === "function" ? e.composedPath() : [];
  for (const el of path) {
    if (el && el.localName === "a" && typeof el.href === "string")
      return el.href;
  }
  return "";
}

window.addEventListener(
  "click",
  (e) => {
    if (
      !choice ||
      !e.isTrusted ||
      e.defaultPrevented ||
      e.button !== 0 ||
      e.ctrlKey ||
      e.shiftKey ||
      e.altKey ||
      e.metaKey
    )
      return;
    const url = linkIn(e);
    if (!url || !wanted(linkTarget(url), choice)) return;
    e.preventDefault();
    e.stopImmediatePropagation();
    browser.runtime.sendMessage({ url }).then(
      (reply) => {
        if (!reply || !reply.ok) location.assign(url);
      },
      () => location.assign(url),
    );
  },
  true,
);

// Play pressed on a video's page (onPlay).

let pressedAt = 0;
let handing = false;
let handedAt = 0;
let playsHere = "";

// The video of this page, when it is one the shell takes on play: a watch
// page (not a Short) and the settings' onPlay.
function pageVideo() {
  if (/^\/shorts\//.test(location.pathname)) return null;
  const t = linkTarget(location.href);
  if (!t || t.kind !== "video") return null;
  return wanted(t, choice, true) && !wanted(t, choice, false) ? t : null;
}

function onPlayer(e) {
  const path = typeof e.composedPath === "function" ? e.composedPath() : [];
  return path.some(
    (el) => el && (el.id === "movie_player" || el.id === "player-container-id"),
  );
}

function editable(el) {
  return (
    !!el &&
    (el.isContentEditable ||
      el.localName === "input" ||
      el.localName === "textarea" ||
      el.localName === "select")
  );
}

function pressed(e) {
  if (e.isTrusted) pressedAt = Date.now();
}

window.addEventListener(
  "pointerdown",
  (e) => {
    if (e.button === 0 && onPlayer(e)) pressed(e);
  },
  true,
);
window.addEventListener(
  "click",
  (e) => {
    if (e.button === 0 && onPlayer(e)) pressed(e);
  },
  true,
);
window.addEventListener(
  "keydown",
  (e) => {
    if (e.ctrlKey || e.altKey || e.metaKey || editable(e.target)) return;
    const k = e.key;
    if (
      k === "k" ||
      k === "K" ||
      k === " " ||
      k === "MediaPlayPause" ||
      k === "MediaPlay" ||
      (k === "Enter" && onPlayer(e))
    )
      pressed(e);
  },
  true,
);

// "play" doesn't bubble: a capture listener on the window still sees it.
window.addEventListener(
  "play",
  (e) => {
    const video = e.target;
    if (!choice || !video || video.localName !== "video") return;
    if (typeof video.closest !== "function" || !video.closest(PLAYERS)) return;
    const page = pageVideo();
    if (!page || playsHere === page.id) return;
    const byUser = Date.now() - pressedAt < PRESS_MS;
    video.pause();
    if (!byUser || handing || Date.now() - handedAt < AGAIN_MS) return;
    pressedAt = 0;
    handing = true;
    // Where it is (an ad playing first: the video's start).
    const ad = !!video.closest(".ad-showing");
    const at = ad ? page.start : Math.floor(video.currentTime || page.start);
    const url = `https://www.youtube.com/watch?v=${page.id}${at > 3 ? `&t=${at}s` : ""}`;
    const done = (taken) => {
      handing = false;
      if (taken) {
        handedAt = Date.now();
        return;
      }
      playsHere = page.id;
      video.play().catch(() => {});
    };
    browser.runtime.sendMessage({ url, played: true }).then(
      (reply) => done(!!reply && reply.ok),
      () => done(false),
    );
  },
  true,
);
