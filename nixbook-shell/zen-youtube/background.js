// nixbook-shell's YouTube links: a page load of a YouTube video, or of a
// YouTube Music song or playlist (linkTarget, links.js: the shell's own
// youtube_links.js), is handed to the shell and stopped here: the video
// plays in mpv, the song in the shell's background player.
//
// Only while the shell wants them: its setting media.youtubeLinks (off by
// default; the menu or Nix), which the native host (nixbook_youtube_links,
// kept running) sends as soon as it changes (`choice`; null: no shell, no
// host). Links the shell doesn't want load as usual, with no round trip.
// When the shell can't take one (not running, not signed in to YouTube
// Music for a playlist) the page loads as usual, and the same link isn't
// asked again for 15 s (so the page loaded instead isn't stopped).
//
// A load stopped here leaves the tab where it was; a tab opened for the
// link alone (a link opening a new tab, a middle click) is closed. Clicks
// inside YouTube's own pages don't load a page (it changes the page in
// place): content.js hands those over, reading the choice from
// storage.local. nixbook's "open in apps" extension asks here
// (runtime.onMessageExternal, {takes: url}) before sending a
// music.youtube.com link to its app.
"use strict";

const NATIVE = "nixbook_youtube_links";
const BLANK = /^about:(blank|newtab|home|privatebrowsing)$/;
const RETRY_MS = 15000;
const ANSWER_MS = 12000;
const refused = new Map();
const pending = new Map();
let port = null;
let choice = null;
let nextId = 1;
let backoff = 1000;

function setChoice(c) {
  choice = c || null;
  browser.storage.local.set({ choice }).catch(() => {});
}

function connect() {
  try {
    port = browser.runtime.connectNative(NATIVE);
  } catch (e) {
    port = null;
    reconnectLater();
    return;
  }
  port.onMessage.addListener((msg) => {
    if (!msg) return;
    if ("choice" in msg) {
      backoff = 1000;
      setChoice(msg.choice);
      return;
    }
    const done = pending.get(msg.id);
    if (done) {
      pending.delete(msg.id);
      done(msg);
    }
  });
  port.onDisconnect.addListener(() => {
    port = null;
    setChoice(null);
    for (const done of pending.values()) done({ ok: false });
    pending.clear();
    reconnectLater();
  });
}

function reconnectLater() {
  setTimeout(connect, backoff);
  backoff = Math.min(backoff * 2, 5 * 60 * 1000);
}

function refusedLately(url) {
  const at = refused.get(url);
  return at !== undefined && Date.now() - at < RETRY_MS;
}

function takes(url) {
  return !!port && wanted(linkTarget(url), choice) && !refusedLately(url);
}

function hand(url) {
  const id = nextId++;
  return new Promise((resolve) => {
    const timer = setTimeout(() => {
      pending.delete(id);
      resolve({ ok: false });
    }, ANSWER_MS);
    pending.set(id, (msg) => {
      clearTimeout(timer);
      resolve(msg);
    });
    try {
      port.postMessage({ id, url });
    } catch (e) {
      pending.delete(id);
      clearTimeout(timer);
      resolve({ ok: false });
    }
  }).then((msg) => {
    const ok = !!(msg && msg.ok);
    if (!ok) {
      const now = Date.now();
      for (const [u, at] of refused)
        if (now - at >= RETRY_MS) refused.delete(u);
      refused.set(url, now);
    }
    return ok;
  });
}

async function tidy(tabId) {
  if (tabId < 0) return;
  try {
    const tab = await browser.tabs.get(tabId);
    if (tab.openerTabId === undefined || !BLANK.test(tab.url || "about:blank"))
      return;
    await browser.tabs.remove(tabId);
  } catch (e) {
    // The tab is gone already.
  }
}

browser.webRequest.onBeforeRequest.addListener(
  (details) => {
    if (details.incognito || !takes(details.url)) return {};
    return hand(details.url).then((ok) => {
      if (!ok) return {};
      setTimeout(() => tidy(details.tabId), 50);
      return { cancel: true };
    });
  },
  {
    urls: [
      "*://youtube.com/*",
      "*://www.youtube.com/*",
      "*://m.youtube.com/*",
      "*://music.youtube.com/*",
      "*://youtu.be/*",
    ],
    types: ["main_frame"],
  },
  ["blocking"],
);

// A click on a video inside YouTube's pages (content.js): {ok}.
browser.runtime.onMessage.addListener((msg, sender) => {
  if (
    sender.id !== browser.runtime.id ||
    (sender.tab && sender.tab.incognito) ||
    !msg ||
    typeof msg.url !== "string" ||
    !takes(msg.url)
  )
    return Promise.resolve({ ok: false });
  return hand(msg.url).then((ok) => ({ ok }));
});

// Another extension sending links to apps (nixbook's "open in apps"): is
// this link the shell's? Says only that.
browser.runtime.onMessageExternal.addListener((msg) => {
  if (!msg || typeof msg.takes !== "string")
    return Promise.resolve({ takes: false });
  return Promise.resolve({ takes: takes(msg.takes) });
});

setChoice(null);
connect();
