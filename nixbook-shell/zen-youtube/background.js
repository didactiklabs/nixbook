// nixbook-shell's YouTube links: a page load of a YouTube video, or of a
// YouTube Music song or playlist (linkTarget, links.js: the shell's own
// youtube_links.js), is handed to the shell and stopped here: the video
// plays in mpv, the song in the shell's background player. With the
// setting media.youtubeLinks.onPlay (on by default) a video's page loads as
// usual and content.js hands the video over when play is pressed on it
// ({url, played: true}).
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
  watchJellyfin();
}

// Jellyfin (the shell's setting media.jellyfinLinks): page loads on the
// server the shell names, while it wants them. Its host isn't known before
// the shell says it, so this listener is set when the choice changes.
// A load in a tab that is already on Jellyfin (browsing its own web page, a
// reload, a restored tab) stays in the browser: only links coming from
// somewhere else play in mpv.
let jellyfinHost = "";

function onJellyfinRequest(details) {
  if (details.incognito || !takes(details.url)) return {};
  const here = (url) => {
    try {
      return new URL(url).host.toLowerCase() === jellyfinHost;
    } catch (e) {
      return false;
    }
  };
  if (details.originUrl && here(details.originUrl)) return {};
  const tab =
    details.tabId < 0
      ? Promise.resolve(null)
      : browser.tabs.get(details.tabId).catch(() => null);
  return tab.then((t) => {
    if (t && here(t.url || "")) return {};
    return hand(details.url).then((ok) => {
      if (!ok) return {};
      setTimeout(() => tidy(details.tabId), 50);
      return { cancel: true };
    });
  });
}

function watchJellyfin() {
  let host = "";
  const jf = choice && choice.jellyfin;
  if (jf && jf.enable === true) {
    try {
      host = new URL(jf.url).host.toLowerCase();
    } catch (e) {
      host = "";
    }
  }
  if (host === jellyfinHost) return;
  browser.webRequest.onBeforeRequest.removeListener(onJellyfinRequest);
  jellyfinHost = host;
  if (host === "") return;
  browser.webRequest.onBeforeRequest.addListener(
    onJellyfinRequest,
    { urls: [`*://${host}/*`], types: ["main_frame"] },
    ["blocking"],
  );
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

function refusedKey(url, played) {
  return played ? `played ${url}` : url;
}

function refusedLately(url, played) {
  const at = refused.get(refusedKey(url, played));
  return at !== undefined && Date.now() - at < RETRY_MS;
}

function takes(url, played) {
  return (
    !!port &&
    wanted(target(url, choice), choice, played === true) &&
    !refusedLately(url, played)
  );
}

function hand(url, played) {
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
      port.postMessage({ id, url, played: played === true });
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
      refused.set(refusedKey(url, played), now);
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

// A click on a video inside YouTube's pages, or play pressed on a video's
// page (content.js, `played`): {ok}.
browser.runtime.onMessage.addListener((msg, sender) => {
  const played = !!msg && msg.played === true;
  if (
    sender.id !== browser.runtime.id ||
    (sender.tab && sender.tab.incognito) ||
    !msg ||
    typeof msg.url !== "string" ||
    !takes(msg.url, played)
  )
    return Promise.resolve({ ok: false });
  return hand(msg.url, played).then((ok) => ({ ok }));
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
