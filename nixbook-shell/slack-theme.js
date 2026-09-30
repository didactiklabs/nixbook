// nixbook-shell: appended to Slack's main-process bundle by slack.nix. Every
// page Slack loads gets the CSS the shell renders from its palette
// (scripts/colors/app-templates/slack.css, written by apply-app-colors.sh) as
// a user stylesheet, swapped live when the file changes and dropped when it
// is removed (the app switched off in the shell's Settings).
(() => {
  try {
    const { app, webContents } = require("electron");
    const fs = require("fs");
    const os = require("os");
    const path = require("path");
    const file = path.join(
      process.env.XDG_STATE_HOME || path.join(os.homedir(), ".local", "state"),
      "quickshell/user/generated/apps/slack.css",
    );
    const read = () => {
      try {
        return fs.readFileSync(file, "utf8");
      } catch {
        return "";
      }
    };
    let css = read();
    // webContents -> key of the stylesheet inserted in its current page
    const inserted = new WeakMap();
    const apply = async (wc) => {
      if (wc.isDestroyed()) return;
      const key = inserted.get(wc);
      inserted.delete(wc);
      if (key) await wc.removeInsertedCSS(key).catch(() => {});
      if (css && !wc.isDestroyed())
        inserted.set(wc, await wc.insertCSS(css, { cssOrigin: "user" }));
    };
    app.on("web-contents-created", (_, wc) => {
      // A new page starts without it: nothing to remove.
      wc.on("did-navigate", () => inserted.delete(wc));
      wc.on("dom-ready", () => apply(wc).catch(() => {}));
    });
    // Polled: works whether the file exists yet or not, and survives the
    // rename it is replaced with.
    fs.watchFile(file, { interval: 1000, persistent: false }, () => {
      const next = read();
      if (next === css) return;
      css = next;
      for (const wc of webContents.getAllWebContents())
        apply(wc).catch(() => {});
    });
  } catch (e) {
    console.error("nixbook-shell theme:", e);
  }
})();
