// nixbook's desktop agents in the browser (nixbook-desktop-mcp's browser_*
// tools): their requests come from the nixbook-zen-bridge native host (a
// private Unix socket on the other side), are done here through the
// WebExtension APIs and the page itself, and answered. No mouse, no
// keyboard: tabs in the background, in another Zen workspace or behind
// another window work the same, and the user keeps working meanwhile.
//
// The page-side code (nixbookPage) is injected only when a tool asks for it.
// Off limits, whatever the agent asks: private windows, password fields, and
// the tabs the request's guard names (sites by regex, containers by name;
// desktop-mcp sends its settings with every request).
"use strict";

const HOST = "nixbook_zen";
let port = null;

function connect() {
  try {
    port = browser.runtime.connectNative(HOST);
  } catch (e) {
    port = null;
    setTimeout(connect, 10000);
    return;
  }
  port.onMessage.addListener(async (msg) => {
    let reply;
    try {
      reply = { id: msg.id, ok: true, result: await handle(msg) };
    } catch (e) {
      reply = { id: msg.id, ok: false, error: String((e && e.message) || e) };
    }
    if (port) port.postMessage(reply);
  });
  // The host gone (Zen keeps no host running when it isn't needed, or it
  // crashed): connected again a little later.
  port.onDisconnect.addListener(() => {
    port = null;
    setTimeout(connect, 5000);
  });
}
connect();

// ── Tabs ──
const containerNames = new Map();
async function containerOf(tab) {
  const id = tab.cookieStoreId;
  if (!id || id === "firefox-default") return "";
  if (!containerNames.has(id)) {
    try {
      containerNames.set(id, (await browser.contextualIdentities.get(id)).name);
    } catch (e) {
      containerNames.set(id, "");
    }
  }
  return containerNames.get(id);
}

function refusedWhy(tab, container, guard) {
  if (tab.incognito) return "a private window";
  const g = guard || {};
  if (
    (g.containers || []).some(
      (c) => c.toLowerCase() === container.toLowerCase() && c,
    )
  )
    return `the ${container} container`;
  for (const s of g.sites || []) {
    try {
      if (new RegExp(s, "i").test(tab.url || ""))
        return "a site the agents may not use";
    } catch (e) {}
  }
  return "";
}

function urlRefused(url, guard) {
  if (!/^https?:\/\//i.test(url)) return "only http and https addresses";
  for (const s of (guard || {}).sites || []) {
    try {
      if (new RegExp(s, "i").test(url)) return "a site the agents may not use";
    } catch (e) {}
  }
  return "";
}

async function describe(tab, guard) {
  const container = await containerOf(tab);
  const out = {
    id: tab.id,
    window: tab.windowId,
    active: tab.active,
    container: container || undefined,
    pinned: tab.pinned || undefined,
    audible: tab.audible || undefined,
    // Zen hides the tabs of its other workspaces.
    otherWorkspace: tab.hidden || undefined,
    loading: tab.status === "loading" || undefined,
  };
  const why = refusedWhy(tab, container, guard);
  if (why) out.private = why;
  else {
    out.title = tab.title;
    out.url = tab.url;
  }
  return out;
}

// The tab asked for (by id), or the one shown in the last focused window.
async function tabFor(msg, allowRefused = false) {
  let tab;
  if (msg.tab !== undefined && msg.tab !== null) {
    try {
      tab = await browser.tabs.get(Number(msg.tab));
    } catch (e) {
      throw new Error(`no tab ${msg.tab} (page_list lists them)`);
    }
  } else {
    [tab] = await browser.tabs.query({ active: true, lastFocusedWindow: true });
    if (!tab) throw new Error("no tab: give `tab` (page_list lists them)");
  }
  if (!allowRefused) {
    const why = refusedWhy(tab, await containerOf(tab), msg.guard);
    if (why)
      throw new Error(
        `refused: tab ${tab.id} is in ${why}; ask the user to do this themselves`,
      );
  }
  return tab;
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

async function waitLoaded(tabId, ms) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    const t = await browser.tabs.get(tabId);
    if (t.status === "complete") return true;
    await sleep(200);
  }
  return false;
}

async function inPage(tab, op, o) {
  const code = `(${nixbookPage.toString()})(${JSON.stringify(op)}, ${JSON.stringify(o || {})})`;
  let results;
  try {
    results = await browser.tabs.executeScript(tab.id, {
      code,
      runAt: "document_idle",
    });
  } catch (e) {
    throw new Error(
      `the page can't be read (${(e && e.message) || e}): a browser page, or still loading`,
    );
  }
  const r = results && results[0];
  if (r && r.error) throw new Error(r.error);
  return r;
}

async function handle(msg) {
  const guard = msg.guard;
  switch (msg.cmd) {
    case "ping":
      return { ok: true, version: browser.runtime.getManifest().version };
    case "tabs": {
      const tabs = await browser.tabs.query({});
      const out = [];
      for (const t of tabs)
        if (!t.incognito) out.push(await describe(t, guard));
      return out;
    }
    case "open": {
      const why = urlRefused(String(msg.url || ""), guard);
      if (why) throw new Error(`refused: ${why}`);
      // In the background unless asked: the user's view doesn't move.
      const tab = await browser.tabs.create({
        url: msg.url,
        active: !!msg.active,
      });
      if (msg.wait !== false) await waitLoaded(tab.id, 15000);
      return describe(await browser.tabs.get(tab.id), guard);
    }
    case "tab": {
      const tab = await tabFor(msg, msg.action === "close");
      switch (msg.action) {
        case "activate":
          await browser.tabs.update(tab.id, { active: true });
          break;
        case "close":
          await browser.tabs.remove(tab.id);
          return { closed: tab.id };
        case "reload":
          await browser.tabs.reload(tab.id);
          break;
        case "back":
          await browser.tabs.goBack(tab.id);
          break;
        case "forward":
          await browser.tabs.goForward(tab.id);
          break;
        case "navigate": {
          const why = urlRefused(String(msg.url || ""), guard);
          if (why) throw new Error(`refused: ${why}`);
          await browser.tabs.update(tab.id, { url: msg.url });
          break;
        }
        case "mute":
        case "unmute":
          await browser.tabs.update(tab.id, { muted: msg.action === "mute" });
          break;
        default:
          throw new Error(
            "action: activate, close, reload, back, forward, navigate, mute or unmute",
          );
      }
      await sleep(300);
      await waitLoaded(tab.id, 15000);
      return describe(await browser.tabs.get(tab.id), guard);
    }
    case "read": {
      const tab = await tabFor(msg);
      const r = await inPage(tab, "read", {
        text: msg.text !== false,
        chars: Math.max(500, Math.min(60000, Number(msg.chars) || 12000)),
        max: Math.max(10, Math.min(400, Number(msg.max) || 150)),
        query: msg.query || "",
      });
      r.tab = tab.id;
      return r;
    }
    case "act": {
      const tab = await tabFor(msg);
      const r = await inPage(tab, "act", {
        ref: msg.ref,
        name: msg.name,
        action: msg.action,
        value: msg.value,
        append: !!msg.append,
      });
      // A click that navigates: its page, once loaded.
      await sleep(400);
      await waitLoaded(tab.id, 10000);
      const after = await browser.tabs.get(tab.id);
      r.tab = tab.id;
      r.url = after.url;
      r.title = after.title;
      return r;
    }
    case "wait": {
      const tab = await tabFor(msg);
      const end =
        Date.now() +
        Math.max(100, Math.min(30000, Number(msg.timeout) || 10000));
      while (Date.now() < end) {
        const t = await browser.tabs.get(tab.id);
        if (
          msg.until === "url"
            ? (t.url || "").includes(msg.text || "")
            : t.status === "complete"
        ) {
          if (msg.until !== "text")
            return { tab: t.id, url: t.url, title: t.title, ok: true };
          try {
            const r = await inPage(t, "has", { text: msg.text });
            if (r && r.found)
              return { tab: t.id, url: t.url, title: t.title, ok: true };
          } catch (e) {}
        }
        await sleep(300);
      }
      return { tab: tab.id, ok: false };
    }
    case "screenshot": {
      const tab = await tabFor(msg);
      const data = await browser.tabs.captureTab(tab.id, {
        format: "jpeg",
        quality: 80,
      });
      return { tab: tab.id, title: tab.title, url: tab.url, data };
    }
    default:
      throw new Error(`unknown command ${msg.cmd}`);
  }
}
