// nixbook-shell's YouTube links (nixbook's opt-in
// nixbookShellConfig.youtubeLinks): a page load of a YouTube video, or of a
// YouTube Music song or playlist (linkTarget, links.js: the shell's own
// youtube_links.js), is handed to the shell (the nixbook_youtube_links
// native host → `nixbook-youtube-link URL`) and stopped here: the video
// plays in mpv, the song in the shell's background player. When the shell
// can't take it (not running, not signed in to YouTube Music for a
// playlist) the page loads as usual, and the same link isn't asked again
// for 15 s (so the page loaded instead isn't stopped).
//
// A load stopped here leaves the tab where it was; a tab opened for the
// link alone (a link opening a new tab, a middle click) is closed. Clicks
// inside YouTube's own pages don't load a page (it changes the page in
// place): content.js hands those over.
"use strict";

const NATIVE = "nixbook_youtube_links";
const BLANK = /^about:(blank|newtab|home|privatebrowsing)$/;
const RETRY_MS = 15000;
const refused = new Map();

function refusedLately(url) {
  const at = refused.get(url);
  return at !== undefined && Date.now() - at < RETRY_MS;
}

async function hand(url) {
  let ok = false;
  try {
    const reply = await browser.runtime.sendNativeMessage(NATIVE, { url });
    ok = !!(reply && reply.ok);
  } catch (e) {
    ok = false;
  }
  if (!ok) {
    const now = Date.now();
    for (const [u, at] of refused) if (now - at >= RETRY_MS) refused.delete(u);
    refused.set(url, now);
  }
  return ok;
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
    if (
      details.incognito ||
      !linkTarget(details.url) ||
      refusedLately(details.url)
    )
      return {};
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
    !linkTarget(msg.url)
  )
    return Promise.resolve({ ok: false });
  return hand(msg.url).then((ok) => ({ ok }));
});
