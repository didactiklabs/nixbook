// nixbook's page code: what the desktop agents read and do in a web page,
// run in the page itself. Shared by Zen's extension (background.js injects
// it into a tab with tabs.executeScript: the extension's isolated world) and
// the Electron apps' bridge (scripts/electron-bridge.py evaluates it over
// the app's private DevTools pipe, in an isolated world of its own): the
// page's own scripts see neither this code nor the references it keeps.
// Password fields are refused, a reference is checked against the
// element's name before acting (a changed page is told, not acted on).
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
  const refs = (window.__nixbookRefs = window.__nixbookRefs || {
    map: new Map(),
  });

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
    const SEL =
      'a[href], button, input:not([type="hidden"]), select, textarea, summary, [role="button"], [role="link"], ' +
      '[role="checkbox"], [role="radio"], [role="tab"], [role="menuitem"], [role="option"], [role="switch"], ' +
      '[role="textbox"], [role="combobox"], [role="searchbox"], [contenteditable=""], [contenteditable="true"]';
    const words = clean(o.query)
      .toLowerCase()
      .split(" ")
      .filter((w) => w);
    refs.map = new Map();
    let n = 0;
    let total = 0;
    const elements = [];
    for (const el of document.querySelectorAll(SEL)) {
      if (!visible(el)) continue;
      total++;
      const name = label(el);
      if (words.length && !words.some((w) => name.toLowerCase().includes(w)))
        continue;
      if (elements.length >= o.max) continue;
      const ref = ++n;
      refs.map.set(ref, el);
      const r = role(el);
      const e = { ref, role: r, name };
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
      elements.push(e);
    }
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

  if (op === "act") {
    const el = refs.map.get(Number(o.ref));
    if (!el || !el.isConnected)
      return { error: "the page changed since page_read: read it again" };
    const now = label(el);
    const want = clean(o.name).toLowerCase();
    if (
      want &&
      !(now.toLowerCase().includes(want) || want.includes(now.toLowerCase()))
    )
      return {
        error: `element ${o.ref} is now ${JSON.stringify(now)}, not ${JSON.stringify(o.name)}: read the page again`,
      };
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
          return { host: "insert" };
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
        if (o.host) return { host: "key", key };
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
    return { done: o.action, element: describeEl(el) };
  }
  return { error: `unknown page operation ${op}` };
}
