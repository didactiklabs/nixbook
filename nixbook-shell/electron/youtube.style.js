// nixbook's colours in YouTube's own design tokens, for ZenPlay (bridged as
// "youtube"). Run by the Electron bridge (scripts/electron-bridge.py's
// `style`) in the page's isolated world, after it put the CSS
// apply-app-colors.sh renders (app-templates/youtube.css) in the page.
//
// YouTube draws nearly everything with custom properties set on the page's
// root: `--yt-sys-color-baseline--text-primary` and, since 2026, hashed
// ones (`--tffc2fd3a644f6275`) no template can name: they are read here,
// from the page's stylesheets. A token is one YouTube gives a light value
// (`:root`, `html`, `[light]`) and a different dark one (`[dark]`); the pair
// says what it is for (a surface, a text colour, an outline, a wash, the
// blue of links and buttons), and it is given the palette's colour for that,
// as one of the `--nixbook-*` variables the CSS defines. The tokens with
// one value for both looks (what is drawn over a video, the brand's red)
// and the other hues (the greens and reds of states) are left alone.
//
// What it writes is one <style> (#nixbook-app-tokens) setting each token on
// the root and on the parts YouTube marks [dark] or [light]; the palette
// changing only changes the variables. Stylesheets added later (YouTube
// loads some with a page) are read when they come.
//
//   nixbookStyle(on) → {tokens: how many were given a colour, mode: the
//   palette's look, "light" or "dark"}
"use strict";

// What a pair of colours is for. L, D: {r, g, b, a} (0-255, a 0-1), the
// token's light and dark values; dark: the palette is a dark one. → a CSS
// value, or null to leave the token alone.
function nixbookTokenColor(L, D, dark) {
  const chroma = (c) => Math.max(c.r, c.g, c.b) - Math.min(c.r, c.g, c.b);
  const grey = (c) => (c.r + c.g + c.b) / 3;
  const hue = (c) => {
    const max = Math.max(c.r, c.g, c.b),
      d = max - Math.min(c.r, c.g, c.b);
    if (!d) return 0;
    const h =
      max === c.r
        ? ((c.g - c.b) / d) % 6
        : max === c.g
          ? (c.b - c.r) / d + 2
          : (c.r - c.g) / d + 4;
    return (h * 60 + 360) % 360;
  };
  const alpha = dark ? D.a : L.a;
  if (alpha === 0) return null;
  const mixed = (name) =>
    alpha >= 1
      ? `var(--nixbook-${name})`
      : `color-mix(in srgb, var(--nixbook-${name}) ${Math.round(alpha * 100)}%, transparent)`;
  const gL = grey(L),
    gD = grey(D);
  if (chroma(L) > 40 || chroma(D) > 40) {
    // A colour. YouTube's blue (links, the buttons that ask for something)
    // is the accent; the other hues say something (an error, live, a
    // member's badge) and stay.
    const strong = chroma(L) >= chroma(D) ? L : D;
    const h = hue(strong);
    if (h < 195 || h > 250) return null;
    if (gL > 200 && gD < 90) return mixed("primary-container");
    if (gL < 90 && gD > 200) return mixed("on-primary-container");
    // The accent of the other look (a link on an inverted surface).
    if (gL > gD + 20) return mixed("inverse-primary");
    return mixed("primary");
  }
  if (gL > gD + 40) {
    // Light in the light look, dark in the dark one: something text is
    // put on. The dark value says how raised it is.
    if (gD <= 0x12) return mixed("surface");
    if (gD <= 0x1d) return mixed("surface-container");
    if (gD <= 0x2c) return mixed("surface-container-high");
    return mixed(gL >= 0xee ? "surface-container-highest" : "outline-variant");
  }
  if (gD > gL + 40)
    // The other way round: text, icons, and the washes made of them.
    return mixed(
      gL <= 0x30 && gD >= 0xd0 ? "on-surface" : "on-surface-variant",
    );
  // Mid greys both ways: disabled text, a border.
  return mixed("outline");
}

// "#fff", "#0f0f0f80", "rgba(0, 0, 0, 0.1)", "rgb(255 255 255 / 20%)",
// "white" → {r, g, b, a}; anything else (a var(), a gradient) → null.
function nixbookParseColor(text) {
  const v = String(text || "")
    .trim()
    .toLowerCase();
  if (v === "white") return { r: 255, g: 255, b: 255, a: 1 };
  if (v === "black") return { r: 0, g: 0, b: 0, a: 1 };
  let m = /^#([0-9a-f]{3,8})$/.exec(v);
  if (m) {
    let h = m[1];
    if (h.length === 3 || h.length === 4)
      h = h
        .split("")
        .map((c) => c + c)
        .join("");
    if (h.length !== 6 && h.length !== 8) return null;
    const n = (i) => parseInt(h.slice(i, i + 2), 16);
    return { r: n(0), g: n(2), b: n(4), a: h.length === 8 ? n(6) / 255 : 1 };
  }
  m = /^rgba?\(([^()]+)\)$/.exec(v);
  if (!m) return null;
  const parts = m[1].split(/[\s,/]+/).filter(Boolean);
  if (parts.length < 3 || parts.length > 4) return null;
  const num = (p, scale) =>
    p.endsWith("%") ? (parseFloat(p) / 100) * scale : parseFloat(p);
  const c = {
    r: num(parts[0], 255),
    g: num(parts[1], 255),
    b: num(parts[2], 255),
    a: parts.length === 4 ? num(parts[3], 1) : 1,
  };
  return [c.r, c.g, c.b, c.a].some((x) => Number.isNaN(x)) ? null : c;
}

// A rule that sets the page's tokens: every selector of its list is made of
// the root (html, :root) and attributes only ("[dark]", "html[dark]",
// "[color-version=\"v2_0\"] [light]"). → "dark", "light" or null.
function nixbookTokenScope(selector) {
  const parts = String(selector || "").split(",");
  let dark = 0;
  for (const part of parts) {
    const rest = part
      .replace(/\[[^\]]*\]/g, "")
      .replace(/:root|html/g, "")
      .trim();
    if (rest) return null;
    if (/\[dark\]/.test(part)) dark++;
  }
  if (dark && dark !== parts.length) return null;
  return dark ? "dark" : "light";
}

// The page's tokens: {name: {light, dark, said: its [light] value seen}}.
function nixbookTokens(sheets) {
  const tokens = {};
  for (const sheet of sheets) {
    let rules;
    try {
      rules = sheet.cssRules;
    } catch (e) {
      continue; // another site's stylesheet
    }
    if (!rules) continue;
    for (const rule of rules) {
      const style = rule.style;
      if (!style || !rule.selectorText || rule.selectorText.length > 160)
        continue;
      const scope = nixbookTokenScope(rule.selectorText);
      if (!scope) continue;
      // The look named outright ([light], [dark]) is the one to believe:
      // a plain `:root` also carries defaults and experiments.
      const said = /\[(light|dark)\]/.test(rule.selectorText);
      for (let i = 0; i < style.length; i++) {
        const name = style[i];
        if (!name.startsWith("--") || name.startsWith("--nixbook-")) continue;
        const color = nixbookParseColor(style.getPropertyValue(name));
        if (!color) continue;
        const t = (tokens[name] = tokens[name] || {});
        if (scope === "light" && t.said && !said) continue;
        t[scope] = color;
        if (scope === "light") t.said = said;
      }
    }
  }
  return tokens;
}

function nixbookTokenCss(tokens, dark) {
  const lines = [];
  for (const name of Object.keys(tokens).sort()) {
    const { light, dark: d } = tokens[name];
    if (!light || !d) continue;
    if (
      light.r === d.r &&
      light.g === d.g &&
      light.b === d.b &&
      light.a === d.a
    )
      continue;
    const value = nixbookTokenColor(light, d, dark);
    if (value) lines.push(`  ${name}: ${value} !important;`);
  }
  return {
    count: lines.length,
    css: lines.length
      ? `:root, [dark], [light] {\n${lines.join("\n")}\n}\n`
      : "",
  };
}

function nixbookStyle(on) {
  const ID = "nixbook-app-tokens";
  const state = (globalThis.nixbookStyleState =
    globalThis.nixbookStyleState || {});
  const stop = () => {
    if (state.observer) state.observer.disconnect();
    state.observer = null;
    clearTimeout(state.timer);
    const old = document.getElementById(ID);
    if (old) old.remove();
  };
  // Its own window (the toolbar around the page): the CSS alone. Another
  // site's page shown in YouTube's place (Google's sign-in): left alone.
  if (!on || !/(^|\.)youtube\.com$/.test(location.hostname)) {
    stop();
    return { tokens: 0 };
  }
  const apply = () => {
    const mode = getComputedStyle(document.documentElement)
      .getPropertyValue("--nixbook-mode")
      .trim();
    const sheets = [...document.styleSheets].filter(
      (s) =>
        !s.ownerNode ||
        (s.ownerNode.id !== ID && s.ownerNode.id !== "nixbook-app-style"),
    );
    const { css, count } = nixbookTokenCss(
      nixbookTokens(sheets),
      mode !== "light",
    );
    let s = document.getElementById(ID);
    if (!s) {
      s = document.createElement("style");
      s.id = ID;
    }
    if (s.textContent !== css) s.textContent = css;
    if (!s.isConnected)
      (document.head || document.documentElement).appendChild(s);
    return { tokens: count, mode: mode === "light" ? "light" : "dark" };
  };
  const result = apply();
  if (!state.observer) {
    // A stylesheet added later (with a page YouTube opens) may bring tokens.
    state.observer = new MutationObserver((records) => {
      const sheet = records.some((r) =>
        [...r.addedNodes].some(
          (n) =>
            n.id !== ID &&
            n.id !== "nixbook-app-style" &&
            (n.nodeName === "STYLE" ||
              (n.nodeName === "LINK" && n.rel === "stylesheet")),
        ),
      );
      if (!sheet) return;
      clearTimeout(state.timer);
      state.timer = setTimeout(apply, 1500);
    });
    state.observer.observe(document.head || document.documentElement, {
      childList: true,
    });
  }
  return result;
}
