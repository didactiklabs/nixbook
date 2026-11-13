// nixbook's "open in apps" (zenBrowserConfig.openInApps): a page load of a
// link on one of the hosts in hosts.js (OPEN_IN_APPS, from Nix) is handed to
// the app that opens it (the nixbook_open_in_app native host) and stopped
// here: a click on a music.youtube.com link plays it in YouTube Music, not in
// a tab. When the host can't (not installed, the app missing) the page loads
// as usual. With nixbookShellConfig.youtubeLinks, YouTube videos and YouTube
// Music songs and playlists are left to the shell's extension.
//
// A load stopped by the extension leaves the tab where it was (no error page,
// no history entry); a tab another tab opened for the link alone (a link
// opening a new tab, a middle click) is left blank, and closed: the tab
// that opened it is still there.
"use strict";

const HOSTS = new Set(OPEN_IN_APPS.map((h) => h.toLowerCase()));
const BLANK = /^about:(blank|newtab|home|privatebrowsing)$/;

function ours(url) {
  // The shell's YouTube links (nixbookShellConfig.youtubeLinks: its own
  // extension takes the videos, songs and playlists; linkTarget, links.js)
  // aren't the app's.
  if (SHELL_YOUTUBE_LINKS && linkTarget(url)) return false;
  try {
    return HOSTS.has(new URL(url).hostname.toLowerCase());
  } catch (e) {
    return false;
  }
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
    if (details.incognito || !ours(details.url)) return {};
    return browser.runtime
      .sendNativeMessage("nixbook_open_in_app", { url: details.url })
      .then((reply) => {
        if (!reply || !reply.ok) return {};
        setTimeout(() => tidy(details.tabId), 50);
        return { cancel: true };
      })
      .catch(() => ({}));
  },
  { urls: OPEN_IN_APPS.map((h) => `*://${h}/*`), types: ["main_frame"] },
  ["blocking"],
);
