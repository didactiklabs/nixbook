// Web pages in the shell's colours (Settings > Appearance > Color generation
// > Apps > Websites (Zen)): Dark Reader's dynamic engine (darkreader.js, its
// library, loaded before this file) on every page and frame, fed the palette
// the shell sends through the native host (background.js keeps it in
// storage.local as pageTheme; a new palette or the switch turned off
// reaches open pages at once).
//
// A dark palette: pages made dark on its surface and text colours; a light
// one: pages made light on them. Links and focus rings take its accent.
"use strict";

// The Dark Reader theme of a stored pageTheme ({mode, background, text,
// selection, scrollbar, accent}).
function nixbookDarkReaderTheme(t) {
  const theme = {
    brightness: 100,
    contrast: 100,
    sepia: 0,
    grayscale: 0,
    selectionColor: t.selection,
    scrollbarColor: t.scrollbar,
  };
  if (t.mode === "light") {
    theme.mode = 0;
    theme.lightSchemeBackgroundColor = t.background;
    theme.lightSchemeTextColor = t.text;
  } else {
    theme.mode = 1;
    theme.darkSchemeBackgroundColor = t.background;
    theme.darkSchemeTextColor = t.text;
  }
  return theme;
}

// The accent on what Dark Reader leaves to the page: links and focus rings.
function nixbookAccentCss(t) {
  return `a:link, a:visited { color: ${t.accent} !important; }
:focus-visible { outline-color: ${t.accent} !important; }
:root { accent-color: ${t.accent}; }`;
}

(() => {
  const DR = globalThis.DarkReader;
  if (!DR || typeof browser === "undefined") return;
  let fetchSet = false;

  // Through the background page (see background.js: fetchForPage).
  function fetchVia(url) {
    return browser.runtime
      .sendMessage({ nixbookFetch: String(url) })
      .then((r) => {
        if (!r || r.error) throw new Error((r && r.error) || "not fetched");
        const raw = atob(r.data);
        const bytes = new Uint8Array(raw.length);
        for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
        return new Response(bytes, {
          status: 200,
          headers: { "content-type": r.type || "" },
        });
      });
  }

  function apply(t) {
    if (!t || !t.enabled) {
      if (DR.isEnabled()) DR.disable();
      return;
    }
    if (!fetchSet) {
      DR.setFetchMethod(fetchVia);
      fetchSet = true;
    }
    DR.enable(nixbookDarkReaderTheme(t), {
      css: nixbookAccentCss(t),
      invert: [],
      ignoreInlineStyle: [],
      ignoreImageAnalysis: [],
    });
  }

  browser.storage.local.get("pageTheme").then(
    (r) => apply(r.pageTheme),
    () => {},
  );
  browser.storage.onChanged.addListener((changes, area) => {
    if (area === "local" && changes.pageTheme)
      apply(changes.pageTheme.newValue);
  });
})();
