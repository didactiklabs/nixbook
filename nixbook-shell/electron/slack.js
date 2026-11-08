// nixbook's Slack operations (the `slack` tool of nixbook-desktop-mcp), run
// by the Electron bridge (scripts/electron-bridge.py) in the Slack app's
// page, through Slack's own Web API the way its client calls it: the
// workspace's API with the session the app already has (its
// localConfig_v2 and cookie, sent by the page itself). No token, cookie or
// header is ever returned (and the bridge scrubs answers for tokens anyway).
//
//   nixbookApp(op, args) → a plain object, or {error}
//
// Operations (`team`: a workspace's name or id, default the one open):
//   status, teams, channels {query?, types?}, users {query?}, find {query},
//   read {channel, limit?, before?}, thread {channel, ts, limit?},
//   send {channel, content, thread_ts?, broadcast?}, schedule {channel,
//   content, at (unix seconds), thread_ts?}, edit {channel, ts, content},
//   delete {channel, ts}, react / unreact {channel, ts, emoji},
//   search {query, limit?}, mark_read {channel, ts?}, pins {channel},
//   pin / unpin {channel, ts}, upload {channel, name, data (base64),
//   content?, thread_ts?}, profile_status {text?, emoji?, minutes?},
//   presence {presence: auto|away}, dnd {minutes}, dnd_end,
//   channel_create {name, private?}, invite {channel, users}, join /
//   leave / archive {channel}, topic {channel, topic}, remind {text, time},
//   api {method, params?}: any other Web API method, but the session's own
//   (auth.*, oauth.*, openid.*), admin.*, apps.* and migration.*.
// A channel is its id (C…, G…, D…), #name, or a person (@name, a name,
// or their U… id: the direct messages with them, opened when needed).
"use strict";

async function nixbookApp(op, o) {
  o = o || {};
  let config = null;
  try {
    config = JSON.parse(localStorage.getItem("localConfig_v2") || "null");
  } catch (e) {
    config = null;
  }
  const teams = config && config.teams ? Object.values(config.teams) : [];
  if (!teams.length)
    return {
      error:
        "Slack isn't signed in (or still loading): ask the user to sign in to the Slack app",
    };

  function fold(s) {
    return String(s || "")
      .normalize("NFKD")
      .replace(/[̀-ͯ]/g, "")
      .toLowerCase()
      .replace(/^[#@]/, "")
      .trim();
  }
  function fail(msg) {
    return { nixbook: msg };
  }
  function team() {
    const want = fold(o.team);
    if (want) {
      const t =
        teams.find((x) => x.id === o.team) ||
        teams.find((x) => fold(x.name) === want || fold(x.domain) === want) ||
        teams.find((x) => fold(x.name).includes(want));
      if (!t)
        throw fail(
          `no workspace ${JSON.stringify(String(o.team))}: ${teams.map((x) => x.name).join(", ")}`,
        );
      return t;
    }
    return (
      (config.lastActiveTeamId && config.teams[config.lastActiveTeamId]) ||
      teams[0]
    );
  }
  const T = team();
  const base = String(T.url || `https://${T.domain}.slack.com/`).replace(
    /\/?$/,
    "/",
  );

  async function api(method, params) {
    const form = new FormData();
    form.append("token", T.token);
    for (const [k, v] of Object.entries(params || {}))
      if (v !== undefined && v !== null)
        form.append(k, typeof v === "object" ? JSON.stringify(v) : String(v));
    const r = await fetch(`${base}api/${method}`, {
      method: "POST",
      body: form,
      credentials: "include",
    });
    let j = null;
    try {
      j = await r.json();
    } catch (e) {
      throw fail(`Slack answered ${r.status} to ${method}`);
    }
    if (!j || !j.ok)
      throw fail(`Slack said: ${(j && j.error) || r.status} (${method})`);
    return j;
  }
  async function paged(method, params, key, max) {
    let out = [];
    let cursor;
    do {
      const j = await api(method, {
        ...params,
        limit: 200,
        ...(cursor ? { cursor } : {}),
      });
      out = out.concat(j[key] || []);
      cursor = j.response_metadata && j.response_metadata.next_cursor;
    } while (cursor && out.length < max);
    return out.slice(0, max);
  }
  let userMap = null;
  async function users() {
    if (!userMap) {
      const list = await paged("users.list", {}, "members", 3000);
      userMap = {};
      for (const u of list) userMap[u.id] = u;
    }
    return userMap;
  }
  function personName(u) {
    if (!u) return "";
    const p = u.profile || {};
    return p.display_name || p.real_name || u.real_name || u.name || u.id;
  }
  async function nameOf(id) {
    return personName((await users())[id]) || id || "";
  }
  async function channels(types) {
    return paged(
      "conversations.list",
      {
        types: types || "public_channel,private_channel,mpim,im",
        exclude_archived: true,
      },
      "channels",
      3000,
    );
  }
  async function describe(c) {
    const out = { id: c.id };
    if (c.is_im) {
      out.kind = "dm";
      out.name = "@" + (await nameOf(c.user));
    } else if (c.is_mpim) {
      out.kind = "group";
      out.name = c.name;
    } else {
      out.kind = c.is_private ? "private" : "channel";
      out.name = "#" + c.name;
    }
    return out;
  }
  function score(name, q) {
    const n = fold(name);
    return !q ? 0 : n === q ? 3 : n.startsWith(q) ? 2 : n.includes(q) ? 1 : 0;
  }
  async function findAll(query) {
    const q = fold(query);
    if (!q) return [];
    const hits = [];
    for (const c of await channels()) {
      const d = await describe(c);
      const s = score(d.name, q);
      if (s) hits.push([s + (c.is_im ? 0.5 : 0), d]);
    }
    const us = await users();
    for (const u of Object.values(us)) {
      if (u.deleted || u.is_bot) continue;
      const s = Math.max(
        score(personName(u), q),
        score(u.name, q),
        score((u.profile || {}).real_name, q),
      );
      if (
        s &&
        !hits.some(([, h]) => h.kind === "dm" && h.name === "@" + personName(u))
      )
        hits.push([s, { id: u.id, kind: "user", name: "@" + personName(u) }]);
    }
    hits.sort((a, b) => b[0] - a[0]);
    return hits.map(([s, h]) => ({ ...h, exact: s >= 3 }));
  }
  async function channelFor(to) {
    const s = String(to || "").trim();
    if (!s) throw fail("`channel`: an id, #name or a person");
    if (/^[CGD][A-Z0-9]{6,}$/.test(s)) return s;
    let user = /^[UW][A-Z0-9]{6,}$/.test(s) ? s : null;
    if (!user) {
      const hits = await findAll(s);
      const exact = hits.filter((h) => h.exact);
      const pick =
        exact.length === 1 ? exact[0] : hits.length === 1 ? hits[0] : null;
      if (!pick)
        throw fail(
          hits.length
            ? `${JSON.stringify(s)} is ambiguous: ${hits
                .slice(0, 6)
                .map((h) => `${h.name} = ${h.id}`)
                .join(", ")}; give the id`
            : `nothing in Slack is called ${JSON.stringify(s)}`,
        );
      if (pick.kind !== "user") return pick.id;
      user = pick.id;
    }
    return (await api("conversations.open", { users: user })).channel.id;
  }
  async function message(m) {
    const out = {
      ts: m.ts,
      author: m.user
        ? await nameOf(m.user)
        : m.username || (m.bot_profile && m.bot_profile.name) || "",
      time: new Date(Number(m.ts) * 1000).toISOString(),
      text: String(m.text || "").slice(0, 3000),
    };
    if (m.user && m.user === T.user_id) out.mine = true;
    if (m.thread_ts && m.thread_ts !== m.ts) out.thread_ts = m.thread_ts;
    if (m.reply_count) out.replies = m.reply_count;
    if ((m.files || []).length)
      out.files = m.files.map((f) => f.name).slice(0, 10);
    if ((m.reactions || []).length)
      out.reactions = m.reactions.map((r) => ({
        emoji: r.name,
        count: r.count,
      }));
    return out;
  }
  function ts(v, what) {
    const s = String(v || "");
    if (!/^\d{9,11}\.\d{1,7}$/.test(s))
      throw fail(`\`${what || "ts"}\`: a message's ts (slack read gives them)`);
    return s;
  }
  function emoji(v) {
    const e = String(v || "")
      .trim()
      .replace(/^:|:$/g, "");
    if (!/^[\w+'-]{1,80}$/.test(e))
      throw fail("`emoji`: its Slack name, e.g. thumbsup or white_check_mark");
    return e;
  }
  const OFF_LIMITS = /^(auth|oauth|openid|admin|apps|migration)\./;

  try {
    switch (op) {
      case "status": {
        const j = await api("auth.test", {});
        return {
          signedIn: true,
          user: await nameOf(j.user_id),
          team: j.team,
          teams: teams.map((t) => t.name),
        };
      }
      case "teams":
        return {
          teams: teams.map((t) => ({
            id: t.id,
            name: t.name,
            domain: t.domain,
          })),
          current: T.name,
        };
      case "channels": {
        const q = fold(o.query);
        const out = [];
        for (const c of await channels(o.types)) {
          const d = await describe(c);
          if (!q || score(d.name, q)) out.push(d);
        }
        return { team: T.name, channels: out.slice(0, 300) };
      }
      case "users": {
        const q = fold(o.query);
        return {
          users: Object.values(await users())
            .filter(
              (u) =>
                !u.deleted &&
                (!q || score(personName(u), q) || score(u.name, q)),
            )
            .slice(0, 300)
            .map((u) => ({
              id: u.id,
              name: personName(u),
              username: u.name,
              bot: !!u.is_bot,
            })),
        };
      }
      case "find":
        return { results: (await findAll(o.query)).slice(0, 20) };
      case "read": {
        const channel = await channelFor(o.channel);
        const limit = Math.max(1, Math.min(100, Number(o.limit) || 20));
        const j = await api("conversations.history", {
          channel,
          limit,
          ...(o.before ? { latest: ts(o.before, "before") } : {}),
        });
        const msgs = [];
        for (const m of (j.messages || []).slice().reverse())
          msgs.push(await message(m));
        return { channel, messages: msgs };
      }
      case "thread": {
        const channel = await channelFor(o.channel);
        const j = await api("conversations.replies", {
          channel,
          ts: ts(o.ts),
          limit: Math.max(1, Math.min(200, Number(o.limit) || 50)),
        });
        const msgs = [];
        for (const m of j.messages || []) msgs.push(await message(m));
        return { channel, messages: msgs };
      }
      case "send": {
        const channel = await channelFor(o.channel);
        const text = String(o.content || "");
        if (!text.trim()) throw fail("`content`: the message");
        const j = await api("chat.postMessage", {
          channel,
          text,
          ...(o.thread_ts ? { thread_ts: ts(o.thread_ts, "thread_ts") } : {}),
          ...(o.broadcast ? { reply_broadcast: true } : {}),
        });
        return { sent: true, ts: j.ts, channel: j.channel };
      }
      case "schedule": {
        const channel = await channelFor(o.channel);
        const at = Math.floor(Number(o.at));
        if (!(at > Date.now() / 1000))
          throw fail("`at`: when, in unix seconds, in the future");
        const j = await api("chat.scheduleMessage", {
          channel,
          text: String(o.content || ""),
          post_at: at,
          ...(o.thread_ts ? { thread_ts: ts(o.thread_ts, "thread_ts") } : {}),
        });
        return { scheduled: j.scheduled_message_id, at, channel };
      }
      case "edit": {
        const channel = await channelFor(o.channel);
        const j = await api("chat.update", {
          channel,
          ts: ts(o.ts),
          text: String(o.content || ""),
        });
        return { edited: j.ts, channel };
      }
      case "delete": {
        const channel = await channelFor(o.channel);
        await api("chat.delete", { channel, ts: ts(o.ts) });
        return { deleted: String(o.ts), channel };
      }
      case "react":
      case "unreact": {
        const channel = await channelFor(o.channel);
        await api(op === "react" ? "reactions.add" : "reactions.remove", {
          channel,
          timestamp: ts(o.ts),
          name: emoji(o.emoji),
        });
        return {
          [op === "react" ? "reacted" : "unreacted"]: emoji(o.emoji),
          ts: String(o.ts),
          channel,
        };
      }
      case "search": {
        const q = String(o.query || "").trim();
        if (!q)
          throw fail(
            "`query`: what to search (Slack's syntax: in:#channel from:@someone…)",
          );
        const j = await api("search.messages", {
          query: q.slice(0, 500),
          count: Math.max(1, Math.min(100, Number(o.limit) || 20)),
        });
        const m = j.messages || {};
        return {
          total: m.total || 0,
          messages: (m.matches || []).map((x) => ({
            ts: x.ts,
            channel: x.channel && x.channel.id,
            where: x.channel && (x.channel.is_im ? "dm" : "#" + x.channel.name),
            author: x.username || "",
            text: String(x.text || "").slice(0, 1500),
          })),
        };
      }
      case "mark_read": {
        const channel = await channelFor(o.channel);
        let at = o.ts ? ts(o.ts) : null;
        if (!at)
          at = ((await api("conversations.history", { channel, limit: 1 }))
            .messages || [{}])[0].ts;
        if (at) await api("conversations.mark", { channel, ts: at });
        return { read: true, channel };
      }
      case "pins": {
        const channel = await channelFor(o.channel);
        const j = await api("pins.list", { channel });
        const msgs = [];
        for (const it of j.items || [])
          if (it.message) msgs.push(await message(it.message));
        return { channel, messages: msgs };
      }
      case "pin":
      case "unpin": {
        const channel = await channelFor(o.channel);
        await api(op === "pin" ? "pins.add" : "pins.remove", {
          channel,
          timestamp: ts(o.ts),
        });
        return {
          [op === "pin" ? "pinned" : "unpinned"]: String(o.ts),
          channel,
        };
      }
      case "upload": {
        const channel = await channelFor(o.channel);
        const name = String(o.name || "file")
          .replace(/[\/\\]/g, "_")
          .slice(0, 120);
        const bytes = Uint8Array.from(atob(String(o.data || "")), (c) =>
          c.charCodeAt(0),
        );
        if (!bytes.length) throw fail("`data`: the file, base64");
        const u = await api("files.getUploadURLExternal", {
          filename: name,
          length: bytes.length,
        });
        const put = await fetch(u.upload_url, {
          method: "POST",
          body: new Blob([bytes]),
        });
        if (!put.ok) throw fail(`the upload failed (${put.status})`);
        await api("files.completeUploadExternal", {
          files: [{ id: u.file_id, title: name }],
          channel_id: channel,
          ...(o.content ? { initial_comment: String(o.content) } : {}),
          ...(o.thread_ts ? { thread_ts: ts(o.thread_ts, "thread_ts") } : {}),
        });
        return { uploaded: name, file: u.file_id, channel };
      }
      case "profile_status": {
        const minutes = Number(o.minutes) || 0;
        await api("users.profile.set", {
          profile: {
            status_text: String(o.text || "").slice(0, 100),
            status_emoji: o.emoji ? ":" + emoji(o.emoji) + ":" : "",
            status_expiration:
              minutes > 0 ? Math.floor(Date.now() / 1000) + minutes * 60 : 0,
          },
        });
        return { status: String(o.text || ""), emoji: o.emoji || "", minutes };
      }
      case "presence": {
        const p = String(o.presence || "");
        if (!["auto", "away"].includes(p)) throw fail("presence: auto or away");
        await api("users.setPresence", { presence: p });
        return { presence: p };
      }
      case "dnd": {
        const minutes = Math.max(1, Math.min(1440, Number(o.minutes) || 60));
        await api("dnd.setSnooze", { num_minutes: minutes });
        return { dnd: minutes };
      }
      case "dnd_end":
        await api("dnd.endSnooze", {});
        return { dnd: "off" };
      case "channel_create": {
        const name = String(o.name || "")
          .trim()
          .toLowerCase()
          .replace(/^#/, "")
          .replace(/\s+/g, "-");
        if (!/^[a-z0-9_-]{1,80}$/.test(name))
          throw fail("`name`: lowercase letters, digits, - and _");
        const j = await api("conversations.create", {
          name,
          is_private: !!o.private,
        });
        return { created: await describe(j.channel) };
      }
      case "invite": {
        const channel = await channelFor(o.channel);
        const ids = [];
        for (const who of Array.isArray(o.users)
          ? o.users.slice(0, 30)
          : [o.users]) {
          const hits = (await findAll(who)).filter(
            (h) => h.kind === "user" || h.kind === "dm",
          );
          const id = /^[UW][A-Z0-9]{6,}$/.test(String(who))
            ? String(who)
            : hits.length === 1 || (hits[0] && hits[0].exact)
              ? hits[0].id
              : null;
          if (!id || id.startsWith("D"))
            throw fail(
              `who is ${JSON.stringify(String(who))}? give their U… id`,
            );
          ids.push(id);
        }
        await api("conversations.invite", { channel, users: ids.join(",") });
        return { invited: ids.length, channel };
      }
      case "join":
      case "leave":
      case "archive": {
        const channel = await channelFor(o.channel);
        await api(`conversations.${op}`, { channel });
        return {
          [op === "join" ? "joined" : op === "leave" ? "left" : "archived"]:
            channel,
        };
      }
      case "topic": {
        const channel = await channelFor(o.channel);
        await api("conversations.setTopic", {
          channel,
          topic: String(o.topic || "").slice(0, 250),
        });
        return { topic: String(o.topic || ""), channel };
      }
      case "remind": {
        const text = String(o.text || "").trim();
        if (!text || !o.time)
          throw fail(
            '`text` and `time` ("in 20 minutes", "tomorrow at 9am" or unix seconds)',
          );
        const j = await api("reminders.add", {
          text: text.slice(0, 500),
          time: String(o.time),
        });
        return { reminder: j.reminder && j.reminder.id };
      }
      case "api": {
        const method = String(o.method || "");
        if (!/^[a-z]+(\.[a-zA-Z0-9]+){1,3}$/.test(method))
          throw fail("method: a Slack Web API method, e.g. bookmarks.list");
        if (OFF_LIMITS.test(method))
          throw fail(
            `refused: ${method} is the session's own or the workspace's admin`,
          );
        const j = await api(
          method,
          o.params && typeof o.params === "object" ? o.params : {},
        );
        delete j.ok;
        return { method, result: j };
      }
      default:
        return { error: `unknown operation ${op}` };
    }
  } catch (e) {
    if (e && typeof e.nixbook === "string") return { error: e.nixbook };
    return { error: String((e && e.message) || e).slice(0, 300) };
  }
}
