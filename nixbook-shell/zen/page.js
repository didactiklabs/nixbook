// nixbook's page code: what the desktop agents read and do in a web page,
// run in the page itself. Shared by Zen's extension (background.js injects
// it into a tab with tabs.executeScript: the extension's isolated world) and
// the Electron apps' bridge (scripts/electron-bridge.py evaluates it over
// the app's private DevTools pipe, in an isolated world of its own): the
// page's own scripts see neither this code nor the references it keeps.
// Password fields are refused, a reference is checked against the
// element's name before acting (a changed page is told, not acted on).
// References are stable: an element keeps its number across reads, and an
// action whose element the page re-rendered finds it again by its name
// when exactly one element has it (or acts by name alone, without a read).
// After an action, "changes" tells what appeared and went since the last
// read, so the agent needn't read the page again.
//
// host: the Electron bridge types and presses keys itself (DevTools'
// Input.insertText / Input.dispatchKeyEvent, which editors such as Slate
// accept and synthetic events aren't): with o.host the "type" and "press"
// actions only focus (and select) the element and say so; "state" reads an
// element back. Zen never sets it.
"use strict";

function nixbookPage(op, o) {
  const clean = (s) =>
    String(s || "")
      .replace(/\s+/g, " ")
      .trim();
  const isPassword = (el) =>
    el.tagName === "INPUT" && (el.type || "").toLowerCase() === "password";
  const visible = (el) => {
    const r = el.getBoundingClientRect();
    if (r.width < 1 || r.height < 1) return false;
    const s = getComputedStyle(el);
    return s.visibility !== "hidden" && s.display !== "none";
  };
  const TAGS = {
    a: "link",
    button: "button",
    select: "list",
    textarea: "text field",
    summary: "summary",
  };
  const role = (el) => {
    const r = el.getAttribute("role");
    if (r) return r;
    const t = el.tagName.toLowerCase();
    if (t === "input") {
      const ty = (el.type || "text").toLowerCase();
      if (ty === "password") return "password field";
      if (["submit", "button", "reset", "image"].includes(ty)) return "button";
      if (
        [
          "checkbox",
          "radio",
          "file",
          "range",
          "color",
          "date",
          "time",
          "datetime-local",
          "month",
          "week",
        ].includes(ty)
      )
        return ty;
      return "text field";
    }
    if (el.isContentEditable) return "text editor";
    return TAGS[t] || t;
  };
  const label = (el) => {
    const by = (el.getAttribute("aria-labelledby") || "")
      .split(/\s+/)
      .map((id) =>
        id && document.getElementById(id)
          ? document.getElementById(id).innerText
          : "",
      )
      .join(" ");
    const labels =
      el.labels && el.labels.length
        ? Array.from(el.labels)
            .map((l) => l.innerText)
            .join(" ")
        : "";
    let own = "";
    if (!["INPUT", "TEXTAREA", "SELECT"].includes(el.tagName))
      own = el.innerText || el.textContent;
    else if (
      ["submit", "button", "reset"].includes((el.type || "").toLowerCase())
    )
      own = el.value;
    return clean(
      el.getAttribute("aria-label") ||
        by ||
        labels ||
        own ||
        el.getAttribute("title") ||
        el.getAttribute("placeholder") ||
        el.getAttribute("alt") ||
        el.getAttribute("name") ||
        "",
    ).slice(0, 120);
  };
  const SEL =
    'a[href], button, input:not([type="hidden"]), select, textarea, summary, [role="button"], [role="link"], ' +
    '[role="checkbox"], [role="radio"], [role="tab"], [role="menuitem"], [role="option"], [role="switch"], ' +
    '[role="textbox"], [role="combobox"], [role="searchbox"], [contenteditable=""], [contenteditable="true"]';
  // ref -> element (the visible ones, as of the last scan), element -> ref
  // (kept while the element lives), the refs and text lines seen at the
  // last read or change report.
  let refs = window.__nixbookRefs;
  if (!refs || !refs.byEl)
    refs = window.__nixbookRefs = {
      map: new Map(),
      byEl: new WeakMap(),
      next: 0,
      seen: null,
      lines: null,
    };
  // Every visible element one can act on, each with its ref.
  const scan = () => {
    refs.map = new Map();
    const out = [];
    for (const el of document.querySelectorAll(SEL)) {
      if (!visible(el)) continue;
      let ref = refs.byEl.get(el);
      if (!ref) {
        ref = ++refs.next;
        refs.byEl.set(el, ref);
      }
      refs.map.set(ref, el);
      out.push({ el, ref });
    }
    return out;
  };
  // The page's text, piece by piece (what a change report compares): its
  // text nodes outside what one acts on (whose names the elements already
  // give), shown ones only.
  const textLines = () => {
    const root =
      document.querySelector("main, article, [role='main']") || document.body;
    const seen = new Set();
    const add = (t) => {
      const c = clean(t);
      if (c.length > 1 && seen.size < 3000) seen.add(c);
    };
    if (!root) return [];
    if (!document.createTreeWalker) {
      for (const l of root.innerText.split("\n")) add(l);
      return [...seen];
    }
    const walk = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    for (let n = walk.nextNode(); n && seen.size < 3000; n = walk.nextNode()) {
      const parent = n.parentElement;
      if (!parent || parent.closest(SEL + ", script, style, noscript"))
        continue;
      if (parent.checkVisibility && !parent.checkVisibility()) continue;
      add(n.nodeValue);
    }
    return [...seen];
  };
  const entry = (el, ref) => {
    const r = role(el);
    const e = { ref, role: r, name: label(el) };
    if (r === "password field") e.password = true;
    else if (
      ["INPUT", "TEXTAREA", "SELECT"].includes(el.tagName) &&
      !["submit", "button", "reset", "checkbox", "radio", "image"].includes(
        (el.type || "").toLowerCase(),
      )
    ) {
      const v = clean(el.value).slice(0, 80);
      if (v) e.value = v;
    }
    if (el.type === "checkbox" || el.type === "radio") e.checked = el.checked;
    else if (el.getAttribute("aria-checked"))
      e.checked = el.getAttribute("aria-checked") === "true";
    if (el.getAttribute("aria-selected") === "true") e.selected = true;
    if (el.disabled || el.getAttribute("aria-disabled") === "true")
      e.disabled = true;
    if (el.tagName === "A" && el.href) e.href = el.href.slice(0, 200);
    if (el.tagName === "SELECT")
      e.options = Array.from(el.options)
        .slice(0, 25)
        .map((x) => clean(x.label || x.text));
    const box = el.getBoundingClientRect();
    if (box.bottom < 0 || box.top > innerHeight) e.offscreen = true;
    return e;
  };

  const describeEl = (el) => {
    if (!el || !el.isConnected) return null;
    const after = { role: role(el), name: label(el) };
    if (["INPUT", "TEXTAREA", "SELECT"].includes(el.tagName) && !isPassword(el))
      after.value = clean(el.value).slice(0, 80);
    else if (o.host && el.isContentEditable)
      after.value = clean(el.innerText).slice(0, 80);
    if (el.type === "checkbox" || el.type === "radio")
      after.checked = el.checked;
    return after;
  };

  if (op === "state") {
    const el = refs.map.get(Number(o.ref));
    return { element: describeEl(el) };
  }

  if (op === "ready")
    return {
      state: document.readyState,
      url: location.href,
      title: document.title,
    };

  if (op === "has") {
    const t = clean(o.text).toLowerCase();
    return {
      found:
        !!t &&
        clean(document.body ? document.body.innerText : "")
          .toLowerCase()
          .includes(t),
    };
  }

  if (op === "read") {
    const words = clean(o.query)
      .toLowerCase()
      .split(" ")
      .filter((w) => w);
    const all = scan();
    const elements = [];
    for (const { el, ref } of all) {
      if (elements.length >= o.max) break;
      const name = label(el);
      if (words.length && !words.some((w) => name.toLowerCase().includes(w)))
        continue;
      elements.push(entry(el, ref));
    }
    const total = all.length;
    refs.seen = new Set(all.map((x) => x.ref));
    refs.lines = new Set(textLines());
    let text = "";
    if (o.text) {
      const root =
        document.querySelector("main, article, [role='main']") || document.body;
      text = (root ? root.innerText : "").replace(/\n{3,}/g, "\n\n").trim();
    }
    return {
      title: document.title,
      url: location.href,
      text: text.slice(0, o.chars),
      textTotal: text.length,
      elements,
      shown: elements.length,
      total,
      selection: clean(String(getSelection())).slice(0, 500),
    };
  }

  // What appeared and went since the last read (or the last report): the
  // page as it is after an action, without reading it all again.
  if (op === "changes") {
    const all = scan();
    const now = new Set(all.map((x) => x.ref));
    const lines = textLines();
    if (!refs.seen) {
      refs.seen = now;
      refs.lines = new Set(lines);
      return { fresh: true, total: all.length };
    }
    const added = all.filter((x) => !refs.seen.has(x.ref));
    let gone = 0;
    for (const r of refs.seen) if (!now.has(r)) gone++;
    const newText = lines
      .filter((l) => !refs.lines.has(l))
      .slice(0, 12)
      .map((l) => l.slice(0, 160));
    refs.seen = now;
    refs.lines = new Set(lines);
    return {
      appeared: added.slice(0, 20).map((x) => entry(x.el, x.ref)),
      appearedTotal: added.length,
      gone,
      newText,
      total: all.length,
    };
  }

  if (op === "act") {
    const want = clean(o.name).toLowerCase();
    let el = o.ref ? refs.map.get(Number(o.ref)) : null;
    const now = el && el.isConnected ? label(el).toLowerCase() : null;
    const fits =
      now !== null &&
      (!want || now.includes(want) || (now && want.includes(now)));
    let refound = false;
    if (!fits) {
      // Gone or renamed (re-rendered): the one element named so now, if
      // there is exactly one — never a guess between several.
      if (!want)
        return {
          error: "the page changed since page_read: read it again",
        };
      const all = scan();
      let found = all.filter((x) => label(x.el).toLowerCase() === want);
      if (found.length === 0)
        found = all.filter((x) => label(x.el).toLowerCase().includes(want));
      if (found.length !== 1) {
        const which = JSON.stringify(o.name);
        if (found.length > 1)
          return {
            error: `${found.length} elements are named ${which}: give its ref (${found
              .slice(0, 6)
              .map(
                (x) =>
                  `[${x.ref}] ${role(x.el)} ${JSON.stringify(label(x.el))}`,
              )
              .join(", ")})`,
          };
        return {
          error: o.ref
            ? `element ${o.ref} is gone and nothing named ${which} is on the page now: read it again`
            : `nothing named ${which} on the page: page_read (with a query) lists what is`,
        };
      }
      el = found[0].el;
      refound = !!o.ref;
    }
    const ref = refs.byEl.get(el);
    if (isPassword(el))
      return {
        error:
          "refused: password fields are off limits; ask the user to do this step",
      };
    const fire = (target) => {
      target.scrollIntoView({ block: "center", inline: "center" });
      try {
        target.focus({ preventScroll: true });
      } catch (e) {}
      const b = target.getBoundingClientRect();
      const at = {
        bubbles: true,
        cancelable: true,
        composed: true,
        view: window,
        button: 0,
        clientX: b.x + b.width / 2,
        clientY: b.y + b.height / 2,
      };
      target.dispatchEvent(
        new PointerEvent(
          "pointerdown",
          Object.assign({ pointerType: "mouse", isPrimary: true }, at),
        ),
      );
      target.dispatchEvent(new MouseEvent("mousedown", at));
      target.dispatchEvent(
        new PointerEvent(
          "pointerup",
          Object.assign({ pointerType: "mouse", isPrimary: true }, at),
        ),
      );
      target.dispatchEvent(new MouseEvent("mouseup", at));
      target.click();
    };
    const changed = (target, data) => {
      target.dispatchEvent(
        new InputEvent("input", {
          bubbles: true,
          inputType: "insertText",
          data,
        }),
      );
      target.dispatchEvent(new Event("change", { bubbles: true }));
    };
    const value =
      o.value === undefined || o.value === null ? "" : String(o.value);
    switch (o.action) {
      case "click":
        fire(el);
        break;
      case "type":
        if (o.host) {
          // The bridge types it (Input.insertText): focused, the old text
          // selected so it is replaced (unless append), the caret at the end.
          if (
            !el.isContentEditable &&
            !["INPUT", "TEXTAREA"].includes(el.tagName)
          )
            return {
              error: `a ${role(el)} takes no text: click it, or pick a text field`,
            };
          el.scrollIntoView({ block: "center" });
          el.focus();
          if (el.isContentEditable) {
            const range = document.createRange();
            range.selectNodeContents(el);
            if (o.append) range.collapse(false);
            const sel = getSelection();
            sel.removeAllRanges();
            sel.addRange(range);
          } else if (o.append) {
            try {
              // Not on every input type (email, number): the caret stays.
              el.setSelectionRange(el.value.length, el.value.length);
            } catch (e) {}
          } else el.select();
          return { host: "insert", ref };
        }
        if (el.isContentEditable) {
          el.focus();
          if (!o.append) document.execCommand("selectAll", false);
          document.execCommand("insertText", false, value);
        } else if (["INPUT", "TEXTAREA"].includes(el.tagName)) {
          el.focus();
          // Through the browser's own setter (this world doesn't see the
          // page's overrides): React and the like see the change.
          el.value = o.append ? el.value + value : value;
          changed(el, value);
        } else
          return {
            error: `a ${role(el)} takes no text: click it, or pick a text field`,
          };
        break;
      case "select": {
        if (el.tagName !== "SELECT")
          return {
            error: "select is for lists (role list): click the option instead",
          };
        const w = value.toLowerCase();
        const opt =
          Array.from(el.options).find(
            (x) =>
              clean(x.label || x.text).toLowerCase() === w ||
              x.value.toLowerCase() === w,
          ) ||
          Array.from(el.options).find((x) =>
            clean(x.label || x.text)
              .toLowerCase()
              .includes(w),
          );
        if (!opt)
          return {
            error: `no option ${JSON.stringify(value)} (they are: ${Array.from(
              el.options,
            )
              .map((x) => clean(x.text))
              .join(", ")})`,
          };
        el.value = opt.value;
        changed(el, opt.value);
        break;
      }
      case "check": {
        const on = !["false", "0", "off", "no"].includes(value.toLowerCase());
        const state =
          el.type === "checkbox" || el.type === "radio"
            ? el.checked
            : el.getAttribute("aria-checked") === "true";
        if (state !== on) fire(el);
        break;
      }
      case "submit": {
        const form = el.form || el.closest("form");
        if (!form) return { error: "not in a form: click its button instead" };
        const isSubmit =
          (el.tagName === "BUTTON" || el.tagName === "INPUT") &&
          (el.type || "").toLowerCase() === "submit";
        form.requestSubmit(isSubmit ? el : undefined);
        break;
      }
      case "press": {
        const key = value || "Enter";
        el.focus();
        if (o.host) return { host: "key", key, ref };
        for (const type of ["keydown", "keypress", "keyup"])
          el.dispatchEvent(
            new KeyboardEvent(type, {
              key,
              code: key.length === 1 ? `Key${key.toUpperCase()}` : key,
              bubbles: true,
              cancelable: true,
            }),
          );
        // Pages don't act on a synthetic Enter: the form is sent the way it would be.
        if (key === "Enter" && el.form && el.tagName === "INPUT")
          el.form.requestSubmit();
        break;
      }
      case "focus":
        el.focus();
        break;
      case "scroll":
        el.scrollIntoView({ block: "center" });
        break;
      default:
        return {
          error:
            "action: click, type, select, check, submit, press, focus or scroll",
        };
    }
    return { done: o.action, element: describeEl(el), ref, refound };
  }
  return { error: `unknown page operation ${op}` };
}
