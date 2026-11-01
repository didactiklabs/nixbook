// nixbook's page code (zen/page.js, shared by Zen's extension and the
// Electron bridge), run here under node on a small fake DOM: references stay
// the same across reads, an action finds a re-rendered element again by its
// name (never guessing between several), and "changes" tells what appeared
// and went. Run by page.sh.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");

class El {
  constructor(tag, name, extra = {}) {
    Object.assign(this, {
      tagName: tag.toUpperCase(),
      attrs: { "aria-label": name },
      innerText: name,
      textContent: name,
      isConnected: true,
      isContentEditable: false,
      labels: null,
      value: "",
      type: "",
      disabled: false,
      form: null,
      clicked: 0,
      ...extra,
    });
  }
  getAttribute(k) {
    return this.attrs[k] ?? null;
  }
  getBoundingClientRect() {
    return { x: 0, y: 10, width: 50, height: 20, top: 10, bottom: 30 };
  }
  focus() {}
  scrollIntoView() {}
  dispatchEvent() {}
  click() {
    this.clicked++;
  }
  closest() {
    return null;
  }
}

let elements = [];
let lines = [];
const body = {
  get innerText() {
    return lines.join("\n");
  },
};
class Ev {}
const ctx = {
  document: {
    title: "Test",
    body,
    querySelectorAll: () => elements.filter((e) => e.isConnected),
    querySelector: () => body,
    getElementById: () => null,
    execCommand: () => true,
  },
  getComputedStyle: () => ({ visibility: "visible", display: "block" }),
  getSelection: () => "",
  innerHeight: 800,
  location: { href: "https://example.org/" },
  PointerEvent: Ev,
  MouseEvent: Ev,
  InputEvent: Ev,
  Event: Ev,
  KeyboardEvent: Ev,
};
ctx.window = ctx;
vm.createContext(ctx);
vm.runInContext(
  fs.readFileSync(path.join(__dirname, "../zen/page.js"), "utf8"),
  ctx,
);
const page = (op, o = {}) => ctx.nixbookPage(op, o);
const read = () =>
  page("read", { text: false, chars: 1000, max: 50, query: "" });

let failed = 0;
function check(name, got, want) {
  const g = JSON.stringify(got);
  const w = JSON.stringify(want);
  if (g === w) return console.log(`ok   - ${name}`);
  failed++;
  console.log(`FAIL - ${name}: got ${g}, want ${w}`);
}
function contains(name, got, part) {
  if (String(got).includes(part)) return console.log(`ok   - ${name}`);
  failed++;
  console.log(
    `FAIL - ${name}: ${JSON.stringify(got)} lacks ${JSON.stringify(part)}`,
  );
}

// A fresh page: "changes" before any read only takes stock.
const save = new El("button", "Save");
const cancel = new El("button", "Cancel");
elements = [save, cancel];
lines = ["Edit your profile"];
check("changes before a read: a fresh page", page("changes"), {
  fresh: true,
  total: 2,
});

let r = read();
check(
  "read: refs in order",
  r.elements.map((e) => [e.ref, e.name]),
  [
    [1, "Save"],
    [2, "Cancel"],
  ],
);
elements = [
  new El("a", "Help", { href: "https://example.org/help" }),
  save,
  cancel,
];
r = read();
check(
  "read again: each element keeps its ref, a new one gets the next",
  r.elements.map((e) => [e.ref, e.name]),
  [
    [3, "Help"],
    [1, "Save"],
    [2, "Cancel"],
  ],
);

// By name alone, no read needed.
let a = page("act", { name: "cancel", action: "click" });
check(
  "act by name alone: that element, its ref",
  [a.done, a.ref, cancel.clicked],
  ["click", 2, 1],
);

// The page re-renders Save: same name, a new element.
const save2 = new El("button", "Save");
save.isConnected = false;
elements = [elements[0], save2, cancel];
a = page("act", { ref: 1, name: "Save", action: "click" });
check(
  "re-rendered: found again by its name, acted on the new one",
  [a.refound, save2.clicked, save.clicked],
  [true, 1, 0],
);

// Never a guess between several.
elements.push(new El("button", "Delete"), new El("button", "Delete"));
a = page("act", { name: "Delete", action: "click" });
contains(
  "two named so: refused, with their refs",
  a.error,
  '2 elements are named "Delete"',
);
a = page("act", { ref: 1, name: "Publish", action: "click" });
contains(
  "its element gone, nothing named so: told",
  a.error,
  'element 1 is gone and nothing named "Publish"',
);
a = page("act", { name: "Publish", action: "click" });
contains(
  "by name, nothing named so: told",
  a.error,
  'nothing named "Publish" on the page',
);
a = page("act", { ref: 2, name: "Cancel", action: "click" });
check(
  "a ref still right: acted, not found again",
  [a.done, a.refound],
  ["click", false],
);

// What an action changed since the last read.
read();
const toast = new El("button", "Undo");
elements = elements.filter((e) => e !== cancel).concat([toast]);
lines = ["Edit your profile", "Saved."];
const c = page("changes");
check(
  "changes: what appeared, with its ref",
  c.appeared.map((e) => [e.role, e.name]),
  [["button", "Undo"]],
);
check("changes: how many went", c.gone, 1);
check("changes: the new text", c.newText, ["Saved."]);
check(
  "changes again: nothing new",
  [page("changes").appeared.length, page("changes").gone],
  [0, 0],
);

// Password fields stay refused, whichever way they are named.
elements.push(new El("input", "Password", { type: "password" }));
contains(
  "password: refused by name too",
  page("act", { name: "Password", action: "type", value: "x" }).error,
  "password fields are off limits",
);

if (failed) {
  console.log(`${failed} failure(s)`);
  process.exit(1);
}
console.log("all page.js tests passed");
