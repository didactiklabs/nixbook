// nixbook-shell's YouTube links, inside YouTube's own pages: a plain click
// on a video there changes the page in place (no page load the background
// page could stop), so it is taken here first and handed to the shell
// (background.js). When the shell can't take it the video opens in the page
// as a normal link would. Ctrl/Shift/middle clicks open a tab or a window:
// a page load, which background.js sees.
"use strict";

window.addEventListener(
  "click",
  (e) => {
    if (
      !e.isTrusted ||
      e.defaultPrevented ||
      e.button !== 0 ||
      e.ctrlKey ||
      e.shiftKey ||
      e.altKey ||
      e.metaKey
    )
      return;
    const path = typeof e.composedPath === "function" ? e.composedPath() : [];
    let url = "";
    for (const el of path) {
      if (el && el.localName === "a" && typeof el.href === "string") {
        url = el.href;
        break;
      }
    }
    if (!url || !linkTarget(url)) return;
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
